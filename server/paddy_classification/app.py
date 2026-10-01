import io
import os
import json

# ============================================================
# ENVIRONMENT
# ============================================================

os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import numpy as np
from PIL import Image, UnidentifiedImageError
from flask import Flask, jsonify, request
from flask_cors import CORS
import tensorflow as tf
from tensorflow.keras.applications.convnext import preprocess_input


# ============================================================
# FLASK APP
# ============================================================

app = Flask(__name__)
CORS(app)


# ============================================================
# BASE PATHS
# ============================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Your actual model:
# E:\peddy\server\paddy_classification\models\paddy_convnext_tiny.keras

MODEL_PATH = os.path.join(
    BASE_DIR,
    "paddy_classification",
    "models",
    "paddy_convnext_tiny.keras"
)

# Class names:
# E:\peddy\server\paddy_classification\models\class_names.json

JSON_PATH = os.path.join(
    BASE_DIR,
    "paddy_classification",
    "models",
    "class_names.json"
)


# ============================================================
# DEFAULT CLASSES
# ============================================================

DEFAULT_CLASSES = [
    "Aumithri",
    "Bpt",
    "Hmt",
    "Ir_64",
    "Mota_Mahamaya",
    "Mota_Paan",
    "Rb_Gold",
    "Sarna"
]


# ============================================================
# LOAD CLASS NAMES
# ============================================================

def load_class_names():

    if os.path.isfile(JSON_PATH):

        try:

            with open(
                JSON_PATH,
                "r",
                encoding="utf-8"
            ) as f:

                data = json.load(f)

            # JSON list:
            # ["Aumithri", "Bpt", ...]

            if isinstance(data, list):

                return data

            # JSON dictionary:
            # {"0": "Aumithri", "1": "Bpt", ...}

            elif isinstance(data, dict):

                try:

                    return [
                        data[str(i)]
                        for i in range(len(data))
                    ]

                except Exception:

                    # Try dictionary values
                    return list(data.values())

        except Exception as e:

            print(
                f"Warning loading class names: {e}"
            )

    print(
        "class_names.json not found. "
        "Using DEFAULT_CLASSES."
    )

    return DEFAULT_CLASSES


CLASSES = load_class_names()

print(
    f"Loaded {len(CLASSES)} paddy classes:"
)

print(CLASSES)


# ============================================================
# MODEL
# ============================================================

_model = None


def get_model():

    global _model

    if _model is None:

        print()
        print("=" * 60)
        print("LOADING PADDY CONVNEXT-TINY MODEL")
        print("=" * 60)

        print(
            "Model path:",
            MODEL_PATH
        )

        # ----------------------------------------------------
        # CHECK MODEL FILE
        # ----------------------------------------------------

        if not os.path.isfile(MODEL_PATH):

            raise FileNotFoundError(
                f"Model file not found: {MODEL_PATH}"
            )

        # ----------------------------------------------------
        # LOAD .KERAS MODEL
        # ----------------------------------------------------

        try:

            _model = tf.keras.models.load_model(
                MODEL_PATH,
                compile=False
            )

        except Exception as e:

            raise RuntimeError(
                f"Failed to load Keras model: {str(e)}"
            )

        # ----------------------------------------------------
        # MODEL INFORMATION
        # ----------------------------------------------------

        print(
            "Model loaded successfully."
        )

        print(
            "Model type:",
            type(_model).__name__
        )

        print(
            "Model input shape:",
            _model.input_shape
        )

        print(
            "Model output shape:",
            _model.output_shape
        )

        print(
            "=" * 60
        )
        print()

    return _model


# ============================================================
# IMAGE LIMIT
# ============================================================

MAX_IMAGE_BYTES = 5 * 1024 * 1024


# ============================================================
# IMAGE PREPROCESSING
# ============================================================

def preprocess_image_bytes(
    file_bytes,
    target_size=(320, 320)
):

    image = Image.open(
        io.BytesIO(file_bytes)
    )

    print(
        "Original image size:",
        image.size
    )

    print(
        "Original image mode:",
        image.mode
    )

    # --------------------------------------------------------
    # Convert to RGB
    # --------------------------------------------------------

    image = image.convert("RGB")

    # --------------------------------------------------------
    # Resize
    # --------------------------------------------------------

    image = image.resize(
        target_size,
        Image.Resampling.BILINEAR
    )

    # --------------------------------------------------------
    # Convert to numpy
    # --------------------------------------------------------

    img_array = np.asarray(
        image,
        dtype=np.float32
    )

    print(
        "Before ConvNeXt preprocessing:",
        "min =",
        float(np.min(img_array)),
        "max =",
        float(np.max(img_array))
    )

    # --------------------------------------------------------
    # Add batch dimension
    # --------------------------------------------------------

    img_array = np.expand_dims(
        img_array,
        axis=0
    )

    # --------------------------------------------------------
    # ConvNeXt preprocessing
    # --------------------------------------------------------

    img_array = preprocess_input(
        img_array
    )

    print(
        "After ConvNeXt preprocessing:",
        "min =",
        float(np.min(img_array)),
        "max =",
        float(np.max(img_array))
    )

    print(
        "Final input shape:",
        img_array.shape
    )

    return img_array


# ============================================================
# CONVERT MODEL OUTPUT TO PROBABILITIES
# ============================================================

def convert_to_probabilities(raw_output):

    values = np.asarray(
        raw_output,
        dtype=np.float32
    )

    values = np.nan_to_num(
        values,
        nan=0.0,
        posinf=0.0,
        neginf=0.0
    )

    output_sum = float(
        np.sum(values)
    )

    print(
        "Raw output sum:",
        output_sum
    )

    print(
        "Raw output min:",
        float(np.min(values))
    )

    print(
        "Raw output max:",
        float(np.max(values))
    )

    # --------------------------------------------------------
    # Model already returns probabilities
    # --------------------------------------------------------

    if (
        np.all(values >= 0)
        and
        np.isclose(
            output_sum,
            1.0,
            atol=0.01
        )
    ):

        print(
            "Output detected as probabilities."
        )

        probabilities = values

    # --------------------------------------------------------
    # Model returns logits
    # --------------------------------------------------------

    else:

        print(
            "Output detected as logits. "
            "Applying softmax."
        )

        probabilities = tf.nn.softmax(
            values
        ).numpy()

    return probabilities


# ============================================================
# ROOT
# ============================================================

@app.route(
    "/",
    methods=["GET"]
)
def index():

    return jsonify({

        "success": True,

        "service":
            "Paddy ConvNeXt-Tiny Classification",

        "architecture":
            "ConvNeXt-Tiny",

        "input_size":
            "320x320",

        "classes":
            CLASSES,

        "endpoint":
            "POST /predict"

    })


# ============================================================
# HEALTH
# ============================================================

@app.route(
    "/health",
    methods=["GET"]
)
def health():

    model_exists = os.path.isfile(
        MODEL_PATH
    )

    return jsonify({

        "success":
            True,

        "status":
            "healthy" if model_exists else "model_missing",

        "service":
            "paddy_classification",

        "architecture":
            "ConvNeXt-Tiny",

        "input_size":
            "320x320",

        "classes":
            CLASSES,

        "total_classes":
            len(CLASSES),

        "model_path":
            MODEL_PATH,

        "model_exists":
            model_exists

    })


# ============================================================
# PREDICTION
# ============================================================

@app.route(
    "/predict",
    methods=["POST"]
)
def predict():

    # --------------------------------------------------------
    # Check image
    # --------------------------------------------------------

    if "image" not in request.files:

        return jsonify({

            "success":
                False,

            "error":
                "No image file provided."

        }), 400


    file = request.files["image"]


    if file.filename == "":

        return jsonify({

            "success":
                False,

            "error":
                "Empty filename."

        }), 400


    file_bytes = file.read()


    if not file_bytes:

        return jsonify({

            "success":
                False,

            "error":
                "Image file is empty."

        }), 400


    # --------------------------------------------------------
    # Image size limit
    # --------------------------------------------------------

    if len(file_bytes) > MAX_IMAGE_BYTES:

        return jsonify({

            "success":
                False,

            "error":
                "Image too large. "
                "Max 5MB. "
                f"Got {len(file_bytes) // 1024}KB."

        }), 400


    try:

        # ====================================================
        # LOAD MODEL
        # ====================================================

        model = get_model()


        # ====================================================
        # PREPROCESS IMAGE
        # ====================================================

        input_data = preprocess_image_bytes(
            file_bytes,
            target_size=(320, 320)
        )


        # ====================================================
        # CONVERT TO TENSOR
        # ====================================================

        input_tensor = tf.convert_to_tensor(
            input_data,
            dtype=tf.float32
        )

        print(
            "Tensor shape:",
            input_tensor.shape
        )

        print(
            "Tensor dtype:",
            input_tensor.dtype
        )


        # ====================================================
        # MODEL INFERENCE
        # ====================================================

        predictions = model(
            input_tensor,
            training=False
        )


        # ====================================================
        # HANDLE MODEL OUTPUT
        # ====================================================

        # Some models return a list/tuple.
        # We expect the classification output.

        if isinstance(
            predictions,
            (list, tuple)
        ):

            predictions = predictions[0]


        # Convert Tensor -> NumPy

        raw_output = predictions.numpy()


        print(
            "========== MODEL OUTPUT DEBUG =========="
        )

        print(
            "Output shape:",
            raw_output.shape
        )

        print(
            "Output dtype:",
            raw_output.dtype
        )

        print(
            "Raw model output:",
            raw_output
        )

        print(
            "========================================"
        )


        # ====================================================
        # REMOVE BATCH DIMENSION
        # ====================================================

        if raw_output.ndim == 2:

            raw_output = raw_output[0]

        elif raw_output.ndim == 1:

            pass

        else:

            return jsonify({

                "success":
                    False,

                "error":
                    "Unexpected model output shape.",

                "output_shape":
                    list(raw_output.shape)

            }), 500


        # ====================================================
        # CHECK OUTPUT SIZE
        # ====================================================

        if len(raw_output) != len(CLASSES):

            return jsonify({

                "success":
                    False,

                "error":
                    "Model output class count does not "
                    "match class_names.json.",

                "model_output_classes":
                    len(raw_output),

                "class_names_count":
                    len(CLASSES),

                "classes":
                    CLASSES

            }), 500


        # ====================================================
        # CONVERT TO PROBABILITIES
        # ====================================================

        probabilities = convert_to_probabilities(
            raw_output
        )


        # ====================================================
        # FINAL PREDICTION
        # ====================================================

        top_index = int(
            np.argmax(probabilities)
        )


        confidence = float(
            probabilities[top_index]
        )


        variety_name = (

            CLASSES[top_index]

            if top_index < len(CLASSES)

            else "Unknown"

        )


        # ====================================================
        # ALL CLASS PREDICTIONS
        # ====================================================

        predictions_map = {}

        for idx, prob in enumerate(
            probabilities
        ):

            if idx < len(CLASSES):

                cls_name = CLASSES[idx]

            else:

                cls_name = (
                    f"class_{idx}"
                )


            predictions_map[cls_name] = round(
                float(prob) * 100,
                2
            )


        # ====================================================
        # SORTED PREDICTIONS
        # ====================================================

        sorted_predictions = sorted(
            predictions_map.items(),
            key=lambda x: x[1],
            reverse=True
        )


        # ====================================================
        # LOGGING
        # ====================================================

        print(
            "========== FINAL PREDICTION =========="
        )

        print(
            "Predicted variety:",
            variety_name
        )

        print(
            "Confidence:",
            round(
                confidence * 100,
                2
            ),
            "%"
        )

        print(
            "Class index:",
            top_index
        )

        print(
            "All predictions:",
            sorted_predictions
        )

        print(
            "======================================"
        )


        # ====================================================
        # RESPONSE
        # ====================================================

        return jsonify({

            "success":
                True,

            "variety":
                variety_name,

            "confidence":
                round(
                    confidence * 100,
                    2
                ),

            "class_index":
                top_index,

            "all_predictions":
                predictions_map

        })


    # ========================================================
    # INVALID IMAGE
    # ========================================================

    except UnidentifiedImageError:

        return jsonify({

            "success":
                False,

            "error":
                "Uploaded file is not a valid image."

        }), 400


    # ========================================================
    # GENERAL ERROR
    # ========================================================

    except Exception as e:

        print(
            "Prediction error:",
            str(e)
        )

        return jsonify({

            "success":
                False,

            "error":
                f"Inference error: {str(e)}"

        }), 500


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    port = int(
        os.environ.get(
            "PORT",
            5000
        )
    )

    print()
    print("=" * 60)
    print("PADDY CLASSIFICATION SERVER")
    print("=" * 60)

    print(
        "BASE_DIR:",
        BASE_DIR
    )

    print(
        "MODEL_PATH:",
        MODEL_PATH
    )

    print(
        "MODEL EXISTS:",
        os.path.isfile(MODEL_PATH)
    )

    print(
        "CLASS NAMES:",
        CLASSES
    )

    print(
        "PORT:",
        port
    )

    print("=" * 60)
    print()

    app.run(
        host="0.0.0.0",
        port=port,
        debug=False
    )
