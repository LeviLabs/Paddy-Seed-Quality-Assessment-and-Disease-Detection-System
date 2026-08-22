import io
import os
import json
import gc

# Force TensorFlow into CPU-only mode and minimize verbose logging
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import numpy as np
from PIL import Image, UnidentifiedImageError
from flask import Flask, jsonify, request
from flask_cors import CORS

import keras
from keras.models import load_model
from keras.layers import Dense
from keras.applications.efficientnet import preprocess_input

app = Flask(__name__)
CORS(app)  # Allow all cross-origin requests

# ============================================================
# COMPATIBLE DENSE LAYER (Fix for legacy Keras models)
# ============================================================

class CompatibleDense(Dense):
    @classmethod
    def from_config(cls, config):
        config = dict(config)
        config.pop("quantization_config", None)
        return super().from_config(config)

# ============================================================
# BASE PATHS & DIRECTORY STRUCTURE
# ============================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")

# 1. Plant Disease Model Paths
DISEASE_MODEL_PATH = os.path.join(MODELS_DIR, "plant_disease", "paddy_disease.keras")
DISEASE_JSON_PATH = os.path.join(MODELS_DIR, "plant_disease", "class_names.json")

# 2. Paddy Classification Model Paths
PADDY_MODEL_PATH = os.path.join(MODELS_DIR, "paddy_classification", "paddy_cnn.keras")
PADDY_JSON_PATH = os.path.join(MODELS_DIR, "paddy_classification", "class_names.json")

# ============================================================
# LOAD CLASS NAMES
# ============================================================

def load_class_names(json_path, fallback):
    if os.path.isfile(json_path):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return [data[str(i)] for i in range(len(data))]
        except Exception as e:
            print(f"Warning loading {json_path}: {e}")
    return fallback

DEFAULT_DISEASE_CLASSES = [
    "bacterial_leaf_blight",
    "bacterial_leaf_streak",
    "bacterial_panicle_blight",
    "blast",
    "brown_spot",
    "dead_heart",
    "downy_mildew",
    "hispa",
    "normal",
    "tungro",
]

DEFAULT_PADDY_CLASSES = ["RB gold", "mota pan dhan"]

DISEASE_CLASSES = load_class_names(DISEASE_JSON_PATH, DEFAULT_DISEASE_CLASSES)
PADDY_CLASSES = load_class_names(PADDY_JSON_PATH, DEFAULT_PADDY_CLASSES)

print(f"Registered {len(DISEASE_CLASSES)} disease classes and {len(PADDY_CLASSES)} paddy classes.")

# ============================================================
# LAZY MODEL LOADERS (Protects 512MB RAM on Render)
# ============================================================

_disease_model = None
_paddy_model = None

def get_disease_model():
    global _disease_model
    if _disease_model is None:
        print(f"Loading Plant Disease Model from {DISEASE_MODEL_PATH}...")
        _disease_model = load_model(
            DISEASE_MODEL_PATH,
            compile=False,
            custom_objects={
                "Dense": CompatibleDense,
                "preprocess_input": preprocess_input,
            },
        )
        print("Plant Disease Model loaded successfully.")
    return _disease_model

def get_paddy_model():
    global _paddy_model
    if _paddy_model is None:
        print(f"Loading Paddy Classification Model from {PADDY_MODEL_PATH}...")
        _paddy_model = load_model(
            PADDY_MODEL_PATH,
            compile=False,
        )
        print("Paddy Classification Model loaded successfully.")
    return _paddy_model

# ============================================================
# IMAGE PREPROCESSING UTILITY
# ============================================================

def preprocess_image_bytes(file_bytes, target_size=(224, 224)):
    """
    Decode and preprocess uploaded image.

    This function includes detailed logging so Render logs can show
    exactly what image bytes reached the server and whether Pillow
    can decode them.
    """
    print("========== IMAGE DEBUG ==========")
    print("Byte length:", len(file_bytes))
    print("First 20 bytes:", file_bytes[:20])

    try:
        # First open and verify the complete image stream.
        image = Image.open(io.BytesIO(file_bytes))
        image.verify()

        # verify() consumes the image object, so reopen it for actual use.
        image = Image.open(io.BytesIO(file_bytes))

        print("PIL format:", image.format)
        print("PIL size:", image.size)
        print("PIL mode:", image.mode)

        # Force actual pixel decoding.
        image.load()

        image = image.convert("RGB")
        image = image.resize(
            target_size,
            Image.Resampling.BILINEAR
        )

        img_array = np.asarray(image, dtype=np.float32)
        img_array = np.expand_dims(img_array, axis=0)

        print("Final array shape:", img_array.shape)
        print("================================")

        return img_array

    except UnidentifiedImageError:
        print("IMAGE DEBUG ERROR: Pillow could not identify this file.")
        print("================================")
        raise

    except Exception as e:
        print("IMAGE DEBUG ERROR:", repr(e))
        print("================================")
        raise

# ============================================================
# DISEASE DESCRIPTIONS & REMEDIES
# ============================================================

DISEASE_INFO = {
    "bacterial_leaf_blight": {
        "description": "Bacterial leaf blight causes water-soaked to yellowish stripes on leaf blades that quickly dry and turn grayish-white.",
        "treatment": "Apply copper hydroxide or streptocycline spray. Ensure balanced potassium fertilization and avoid excess nitrogen.",
    },
    "bacterial_leaf_streak": {
        "description": "Appears as narrow, brownish-yellow interveinal streaks with tiny amber bacterial exudates.",
        "treatment": "Ensure proper drainage and balanced nitrogen. Apply copper fungicides if symptoms appear early.",
    },
    "bacterial_panicle_blight": {
        "description": "Causes discoloration of panicles and florets, resulting in sterile or partially filled grains.",
        "treatment": "Use disease-free certified seeds. Avoid excess nitrogen during heading stage.",
    },
    "blast": {
        "description": "Diamond-shaped or spindle-like lesions with gray or white centers and brown margins on leaves and panicle neck.",
        "treatment": "Apply Tricyclazole or Azoxystrobin. Avoid high nitrogen and maintain continuous shallow flooding.",
    },
    "brown_spot": {
        "description": "Small, round to oval brown spots with yellowish halos on leaves and glumes, often associated with soil nutrient deficiency.",
        "treatment": "Apply Mancozeb or Propiconazole. Correct soil fertility by adding potash and micronutrients.",
    },
    "dead_heart": {
        "description": "Drying and death of the central tiller shoot caused by yellow stem borer larval feeding.",
        "treatment": "Apply Cartap hydrochloride or Chlorantraniliprole granules. Install pheromone traps.",
    },
    "downy_mildew": {
        "description": "Stunted growth, yellow-white speckles, and chlorotic patches on leaves with distorted panicles.",
        "treatment": "Improve field drainage and treat seeds with Metalaxyl before planting.",
    },
    "hispa": {
        "description": "Leaf scraping and white parallel streaks caused by the spiny black hispa beetle feeding on green tissue.",
        "treatment": "Clip affected leaf tips before transplanting. Spray Chlorpyrifos or Quinalphos if infestation exceeds threshold.",
    },
    "normal": {
        "description": "The leaf appears healthy with no visible signs of pathogenic fungal, bacterial, or insect damage.",
        "treatment": "Maintain regular watering, balanced N-P-K fertilization, and monitor weekly for early pest detection.",
    },
    "tungro": {
        "description": "Viral disease transmitted by green leafhoppers causing severe stunting and bright yellow to orange-yellow leaf discoloration.",
        "treatment": "Control green leafhopper vectors with Imidacloprid. Remove infected stubble and use resistant varieties.",
    },
}

# ============================================================
# API ROUTES
# ============================================================

@app.route("/", methods=["GET"])
def index():
    return jsonify({
        "success": True,
        "message": "Paddy AI Backend is running.",
        "endpoints": [
            "GET  /health",
            "POST /predict/plant-disease",
            "POST /predict/paddy-classification",
        ],
    })

@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "success": True,
        "status": "healthy",
        "models": {
            "plant_disease": {
                "classes": DISEASE_CLASSES,
                "total_classes": len(DISEASE_CLASSES),
                "model_file": os.path.basename(DISEASE_MODEL_PATH),
                "exists": os.path.isfile(DISEASE_MODEL_PATH),
            },
            "paddy_classification": {
                "classes": PADDY_CLASSES,
                "total_classes": len(PADDY_CLASSES),
                "model_file": os.path.basename(PADDY_MODEL_PATH),
                "exists": os.path.isfile(PADDY_MODEL_PATH),
            },
        },
    })

# ============================================================
# ENDPOINT: PLANT DISEASE PREDICTION
# ============================================================

@app.route("/predict/plant-disease", methods=["POST"])
def predict_plant_disease():
    if "image" not in request.files:
        return jsonify({
            "success": False,
            "error": "No image file provided in request.",
        }), 400

    file = request.files["image"]
    if file.filename == "":
        return jsonify({
            "success": False,
            "error": "Empty filename provided.",
        }), 400

    try:
        # Read and inspect the uploaded file BEFORE loading the TensorFlow model.
        file_bytes = file.read()

        print("========== UPLOAD DEBUG ==========")
        print("Filename:", file.filename)
        print("Content-Type:", file.content_type)
        print("File size:", len(file_bytes))
        print("First 20 bytes:", file_bytes[:20])
        print("==================================")

        if not file_bytes:
            return jsonify({
                "success": False,
                "error": "Image file is empty.",
            }), 400

        # Decode/validate the image before loading the model.
        input_data = preprocess_image_bytes(file_bytes)

        # Only load the model after the image is confirmed readable.
        model = get_disease_model()

        # Run inference
        raw_predictions = model.predict(input_data, batch_size=1, verbose=0)[0]
        probabilities = [float(p) for p in raw_predictions]

        top_index = int(np.argmax(probabilities))
        disease_name = DISEASE_CLASSES[top_index] if top_index < len(DISEASE_CLASSES) else "unknown"
        confidence = probabilities[top_index]

        # Build class breakdown
        predictions_map = {}
        for idx, prob in enumerate(probabilities):
            cls_name = DISEASE_CLASSES[idx] if idx < len(DISEASE_CLASSES) else f"class_{idx}"
            predictions_map[cls_name] = round(prob * 100, 2)

        info = DISEASE_INFO.get(disease_name, {
            "description": "Agricultural diagnosis complete.",
            "treatment": "Follow standard crop protection guidelines.",
        })

        return jsonify({
            "success": True,
            "disease": disease_name,
            "confidence": round(confidence * 100, 2),
            "class_index": top_index,
            "description": info["description"],
            "treatment": info["treatment"],
            "predictions": predictions_map,
        })

    except UnidentifiedImageError as e:
        print("PLANT DISEASE IMAGE ERROR:", repr(e))
        return jsonify({
            "success": False,
            "error": "Uploaded file is not a valid or readable image.",
            "details": repr(e),
        }), 400
    except Exception as e:
        print(f"Error during plant disease prediction: {e}")
        return jsonify({
            "success": False,
            "error": f"Inference error: {str(e)}",
        }), 500

# ============================================================
# ENDPOINT: PADDY CLASSIFICATION
# ============================================================

@app.route("/predict/paddy-classification", methods=["POST"])
def predict_paddy_classification():
    if "image" not in request.files:
        return jsonify({
            "success": False,
            "error": "No image file provided in request.",
        }), 400

    file = request.files["image"]
    if file.filename == "":
        return jsonify({
            "success": False,
            "error": "Empty filename provided.",
        }), 400

    try:
        # Read and inspect the uploaded file BEFORE loading the TensorFlow model.
        file_bytes = file.read()

        print("========== PADDY UPLOAD DEBUG ==========")
        print("Filename:", file.filename)
        print("Content-Type:", file.content_type)
        print("File size:", len(file_bytes))
        print("First 20 bytes:", file_bytes[:20])
        print("========================================")

        if not file_bytes:
            return jsonify({
                "success": False,
                "error": "Image file is empty.",
            }), 400

        # Decode/validate the image before loading the model.
        input_data = preprocess_image_bytes(file_bytes)

        # Only load the model after the image is confirmed readable.
        model = get_paddy_model()

        # Run inference
        raw_pred = model.predict(input_data, batch_size=1, verbose=0)[0]

        if len(raw_pred) == 1:
            prob_class_1 = float(raw_pred[0])
            if prob_class_1 >= 0.5:
                top_index = 1
                confidence = prob_class_1
            else:
                top_index = 0
                confidence = 1.0 - prob_class_1
        else:
            top_index = int(np.argmax(raw_pred))
            confidence = float(raw_pred[top_index])

        variety_name = PADDY_CLASSES[top_index] if top_index < len(PADDY_CLASSES) else "Unknown"

        return jsonify({
            "success": True,
            "variety": variety_name,
            "confidence": round(confidence * 100, 2),
            "class_index": top_index,
        })

    except UnidentifiedImageError as e:
        print("PADDY IMAGE ERROR:", repr(e))
        return jsonify({
            "success": False,
            "error": "Uploaded file is not a valid or readable image.",
            "details": repr(e),
        }), 400
    except Exception as e:
        print(f"Error during paddy classification: {e}")
        return jsonify({
            "success": False,
            "error": f"Inference error: {str(e)}",
        }), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)