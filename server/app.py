import os
import threading

import numpy as np
from PIL import Image, UnidentifiedImageError
from flask import Flask, jsonify, request

import keras
from keras.models import load_model
from keras.layers import Dense
from keras.applications.efficientnet import preprocess_input


app = Flask(__name__)


# ============================================================
# COMPATIBLE DENSE LAYER
# ============================================================
#
# Your saved model contains:
#
#     "quantization_config": None
#
# in some Dense layer configurations.
#
# The current Dense implementation rejects that field.
# We remove it only during model deserialization.
# ============================================================

class CompatibleDense(Dense):
    @classmethod
    def from_config(cls, config):
        config = dict(config)

        config.pop(
            "quantization_config",
            None,
        )

        return super().from_config(config)


# ============================================================
# MODEL
# ============================================================

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)

MODEL_PATH = os.path.join(
    BASE_DIR,
    "models",
    "plant_disease",
    "best_paddy_disease_model_fixed.keras",
)

print("Loading model from:")
print(MODEL_PATH)

if not os.path.isfile(MODEL_PATH):
    raise FileNotFoundError(
        f"Model file not found: {MODEL_PATH}"
    )

print("Model file exists.")

print(
    "TensorFlow/Keras runtime:"
)

try:
    import tensorflow as tf

    print(
        "TensorFlow:",
        tf.__version__,
    )
except Exception:
    tf = None


print(
    "Keras:",
    keras.__version__,
)


# ============================================================
# LOAD MODEL
# ============================================================

model = load_model(
    MODEL_PATH,
    compile=False,
    custom_objects={
        "Dense": CompatibleDense,
        "preprocess_input": preprocess_input,
    },
)

print(
    "Plant disease model loaded successfully."
)

print(
    "Model input shape:",
    model.input_shape,
)

print(
    "Model output shape:",
    model.output_shape,
)


# ============================================================
# PREDICTION LOCK
# ============================================================
#
# Keep only one TensorFlow inference active at a time.
# This is especially important on the Render Free instance.
# ============================================================

prediction_lock = threading.Lock()


# ============================================================
# CLASS NAMES
# ============================================================

CLASS_NAMES = [
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


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "success": True,
        "message": "Paddy Disease API is running",
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "success": True,
        "status": "healthy",
        "model": "best_paddy_disease_model_fixed.keras",
        "input_shape": str(
            model.input_shape
        ),
        "output_shape": str(
            model.output_shape
        ),
        "classes": CLASS_NAMES,
    })


# ============================================================
# IMAGE PREPROCESSING
# ============================================================

def preprocess_image(image):
    """
    The saved model contains the EfficientNet
    preprocess_input Lambda layer.

    Therefore do NOT divide by 255 here.
    """

    image = image.convert("RGB")

    image = image.resize(
        (224, 224),
        Image.Resampling.BILINEAR,
    )

    image_array = np.asarray(
        image,
        dtype=np.float32,
    )

    image_array = np.expand_dims(
        image_array,
        axis=0,
    )

    return image_array


# ============================================================
# PLANT DISEASE PREDICTION
# ============================================================

@app.route(
    "/predict/plant-disease",
    methods=["POST"],
)
def predict_plant_disease():

    # ----------------------------------------------------------
    # CHECK IMAGE
    # ----------------------------------------------------------

    if "image" not in request.files:
        return jsonify({
            "success": False,
            "error": "No image uploaded",
        }), 400

    file = request.files["image"]

    if (
        file is None
        or file.filename == ""
    ):
        return jsonify({
            "success": False,
            "error": "No image selected",
        }), 400

    image = None

    try:

        # ------------------------------------------------------
        # OPEN IMAGE
        # ------------------------------------------------------

        image = Image.open(
            file.stream
        )

        # Verify that the uploaded file really is
        # a readable image.
        image.verify()

        # Re-open after verify because verify() invalidates
        # the image object for normal loading.
        file.stream.seek(0)

        image = Image.open(
            file.stream
        )

        # ------------------------------------------------------
        # BASIC IMAGE SAFETY
        # ------------------------------------------------------

        # Avoid accidentally processing extremely large
        # decompressed images.
        max_dimension = 6000

        if (
            image.width > max_dimension
            or image.height > max_dimension
        ):
            return jsonify({
                "success": False,
                "error": (
                    "Image is too large. "
                    "Please upload a smaller image."
                ),
            }), 400

        print(
            "Received image:",
            image.width,
            "x",
            image.height,
        )

        # ------------------------------------------------------
        # PREPROCESS
        # ------------------------------------------------------

        input_data = preprocess_image(
            image
        )

        print(
            "Prepared model input:",
            input_data.shape,
            input_data.dtype,
        )

        # ------------------------------------------------------
        # PREDICT
        # ------------------------------------------------------
        #
        # Only one inference at a time.
        # This avoids multiple TensorFlow executions
        # competing for the limited Render Free CPU/RAM.
        # ------------------------------------------------------

        with prediction_lock:

            print(
                "Starting plant disease inference..."
            )

            output = model(
                input_data,
                training=False,
            )

            predictions = output.numpy()

            print(
                "Plant disease inference completed."
            )

        # ------------------------------------------------------
        # OUTPUT
        # ------------------------------------------------------

        probabilities = np.asarray(
            predictions[0]
        )

        if (
            probabilities.ndim
            != 1
        ):
            probabilities = (
                probabilities.flatten()
            )

        # ------------------------------------------------------
        # CHECK OUTPUT SIZE
        # ------------------------------------------------------

        if len(probabilities) != len(
            CLASS_NAMES
        ):
            return jsonify({
                "success": False,
                "error": (
                    "Model output size does "
                    "not match CLASS_NAMES. "
                    f"Model output: "
                    f"{len(probabilities)}, "
                    f"Classes: "
                    f"{len(CLASS_NAMES)}"
                ),
            }), 500

        # ------------------------------------------------------
        # PREDICTED CLASS
        # ------------------------------------------------------

        predicted_index = int(
            np.argmax(
                probabilities
            )
        )

        confidence = float(
            probabilities[
                predicted_index
            ]
        )

        predicted_class = (
            CLASS_NAMES[
                predicted_index
            ]
        )

        # ------------------------------------------------------
        # ALL PREDICTIONS
        # ------------------------------------------------------

        all_predictions = {}

        for (
            index,
            class_name,
        ) in enumerate(
            CLASS_NAMES
        ):
            all_predictions[
                class_name
            ] = round(
                float(
                    probabilities[
                        index
                    ]
                ) * 100,
                2,
            )

        # ------------------------------------------------------
        # RESPONSE
        # ------------------------------------------------------

        result = {
            "success": True,
            "test_type": "plant_disease",
            "disease": predicted_class,
            "confidence": round(
                confidence * 100,
                2,
            ),
            "class_index": predicted_index,
            "predictions": all_predictions,
        }

        print(
            "Prediction result:",
            result,
        )

        return jsonify(
            result
        )

    except UnidentifiedImageError:
        print(
            "Prediction error: uploaded file "
            "is not a valid image."
        )

        return jsonify({
            "success": False,
            "error": "Uploaded file is not a valid image.",
        }), 400

    except Exception as e:

        print(
            "Prediction error:",
            repr(e),
        )

        return jsonify({
            "success": False,
            "error": str(e),
        }), 500

    finally:

        if image is not None:
            try:
                image.close()
            except Exception:
                pass


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    port = int(
        os.environ.get(
            "PORT",
            10000,
        )
    )

    print(
        f"Starting server on port {port}"
    )

    app.run(
        host="0.0.0.0",
        port=port,
        debug=False,
    )