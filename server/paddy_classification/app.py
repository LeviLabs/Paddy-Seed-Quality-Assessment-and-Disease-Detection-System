import io
import os
import json
import hashlib
import traceback

# ============================================================
# TENSORFLOW SETTINGS
# ============================================================

os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

# ============================================================
# IMPORTS
# ============================================================

import numpy as np
from PIL import Image, UnidentifiedImageError

from flask import Flask, jsonify, request
from flask_cors import CORS

import tensorflow as tf


# ============================================================
# FLASK APP
# ============================================================

app = Flask(__name__)
CORS(app)


# ============================================================
# PATHS
# ============================================================

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)

MODEL_DIR = os.path.join(
    BASE_DIR,
    "models"
)

MODEL_PATH = os.path.join(
    MODEL_DIR,
    "best_paddy_resnet50.keras"
)

JSON_PATH = os.path.join(
    MODEL_DIR,
    "class_names.josan"
)


# ============================================================
# SERVER START DEBUG
# ============================================================

print()
print("================================================")
print("PADDY CLASSIFICATION SERVER")
print("================================================")

print("BASE_DIR:")
print(BASE_DIR)

print("MODEL_DIR:")
print(MODEL_DIR)

print("MODEL_PATH:")
print(MODEL_PATH)

print(
    "MODEL EXISTS:",
    os.path.isfile(MODEL_PATH)
)

print(
    "CLASS JSON EXISTS:",
    os.path.isfile(JSON_PATH)
)

print("================================================")
print()


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

            # Example:
            # [
            #   "Aumithri",
            #   "Bpt",
            #   ...
            # ]

            if isinstance(data, list):

                return data

            # Example:
            # {
            #   "0": "Aumithri",
            #   "1": "Bpt"
            # }

            if isinstance(data, dict):

                try:

                    return [
                        data[str(i)]
                        for i in range(len(data))
                    ]

                except Exception:

                    return list(data.values())

        except Exception as e:

            print(
                "CLASS JSON ERROR:",
                str(e)
            )

    print("Using DEFAULT_CLASSES.")

    return DEFAULT_CLASSES


CLASSES = load_class_names()

print(
    "Loaded classes:",
    CLASSES
)


# ============================================================
# MODEL GLOBAL
# ============================================================

_model = None


# ============================================================
# LOAD KERAS MODEL
# ============================================================

def get_model():

    global _model

    if _model is not None:
        return _model

    print()
    print("================================================")
    print("LOADING KERAS MODEL")
    print("================================================")

    print(
        "Path:",
        MODEL_PATH
    )

    if not os.path.isfile(MODEL_PATH):

        raise FileNotFoundError(
            f"Keras model not found: {MODEL_PATH}"
        )

    print(
        "Loading best_paddy_resnet50.keras..."
    )

    _model = tf.keras.models.load_model(
        MODEL_PATH,
        compile=False
    )

    print(
        "Model loaded successfully."
    )

    print(
        "Model name:",
        _model.name
    )

    print(
        "Input shape:",
        _model.input_shape
    )

    print(
        "Output shape:",
        _model.output_shape
    )

    print("================================================")
    print("MODEL READY")
    print("================================================")
    print()

    return _model


# ============================================================
# DETECT MODEL INPUT SIZE
# ============================================================

def get_model_input_size():

    model = get_model()

    input_shape = model.input_shape

    # Handle models with multiple inputs
    if isinstance(input_shape, list):
        input_shape = input_shape[0]

    try:

        height = input_shape[1]
        width = input_shape[2]

        if (
            height is not None
            and
            width is not None
        ):

            return (
                int(width),
                int(height)
            )

    except Exception:

        pass

    # Standard ResNet50 size
    return (224, 224)


# ============================================================
# IMAGE SETTINGS
# ============================================================

MAX_IMAGE_BYTES = (
    5 * 1024 * 1024
)


# ============================================================
# IMAGE PREPROCESSING
# ============================================================

def preprocess_image_bytes(
    file_bytes
):

    target_size = get_model_input_size()

    print(
        "Target model size:",
        target_size
    )

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

    image = image.convert(
        "RGB"
    )

    image = image.resize(
        target_size,
        Image.Resampling.BILINEAR
    )

    img_array = np.asarray(
        image,
        dtype=np.float32
    )

    print(
        "Image min before preprocessing:",
        float(np.min(img_array))
    )

    print(
        "Image max before preprocessing:",
        float(np.max(img_array))
    )

    print(
        "Image mean before preprocessing:",
        float(np.mean(img_array))
    )

    # ========================================================
    # RESNET50 PREPROCESSING
    # ========================================================
    #
    # IMPORTANT:
    #
    # If your training code used:
    #
    # tf.keras.applications.resnet50.preprocess_input(...)
    #
    # then keep this line enabled.
    #
    # ========================================================

    img_array = tf.keras.applications.resnet50.preprocess_input(
        img_array
    )

    img_array = np.expand_dims(
        img_array,
        axis=0
    )

    print(
        "Final input shape:",
        img_array.shape
    )

    print(
        "Final dtype:",
        img_array.dtype
    )

    print(
        "Final min:",
        float(np.min(img_array))
    )

    print(
        "Final max:",
        float(np.max(img_array))
    )

    return img_array


# ============================================================
# RUN MODEL
# ============================================================

def run_inference(
    input_tensor
):

    model = get_model()

    print(
        "Running inference..."
    )

    outputs = model(
        input_tensor,
        training=False
    )

    return outputs


# ============================================================
# EXTRACT MODEL OUTPUT
# ============================================================

def extract_raw_output(
    outputs
):

    print()
    print(
        "========== MODEL OUTPUT =========="
    )

    # Some Keras models may return dictionary outputs
    if isinstance(outputs, dict):

        keys = list(outputs.keys())

        print(
            "Output keys:",
            keys
        )

        if not keys:

            raise RuntimeError(
                "Model returned an empty dictionary."
            )

        output_tensor = outputs[
            keys[0]
        ]

    # Some models may return list/tuple
    elif isinstance(outputs, (list, tuple)):

        if len(outputs) == 0:

            raise RuntimeError(
                "Model returned an empty output list."
            )

        output_tensor = outputs[0]

    else:

        output_tensor = outputs


    if tf.is_tensor(output_tensor):

        output_array = output_tensor.numpy()

    else:

        output_array = np.asarray(
            output_tensor
        )


    print(
        "Full output shape:",
        output_array.shape
    )


    if output_array.ndim > 1:

        raw_output = output_array[0]

    else:

        raw_output = output_array


    raw_output = np.asarray(
        raw_output,
        dtype=np.float32
    )


    print(
        "RAW MODEL OUTPUT:"
    )

    print(
        raw_output
    )

    print(
        "RAW ARGMAX:",
        int(np.argmax(raw_output))
    )

    print(
        "RAW SUM:",
        float(np.sum(raw_output))
    )

    print(
        "RAW MIN:",
        float(np.min(raw_output))
    )

    print(
        "RAW MAX:",
        float(np.max(raw_output))
    )

    print(
        "=================================="
    )

    return raw_output


# ============================================================
# CONVERT OUTPUT TO PROBABILITIES
# ============================================================

def convert_to_probabilities(
    raw_output
):

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

    total = float(
        np.sum(values)
    )


    # ========================================================
    # MODEL ALREADY RETURNS SOFTMAX PROBABILITIES
    # ========================================================

    if (
        np.all(values >= 0)
        and
        np.all(values <= 1)
        and
        np.isclose(
            total,
            1.0,
            atol=0.01
        )
    ):

        print(
            "Output already probabilities."
        )

        probabilities = values


    # ========================================================
    # MODEL RETURNS LOGITS
    # ========================================================

    else:

        print(
            "Output appears to be logits."
        )

        print(
            "Applying softmax."
        )

        probabilities = (
            tf.nn.softmax(
                values
            ).numpy()
        )


    print()
    print(
        "FINAL PROBABILITIES:"
    )

    print(
        probabilities
    )

    print(
        "FINAL ARGMAX:",
        int(np.argmax(probabilities))
    )

    print(
        "FINAL MAX CONFIDENCE:",
        float(np.max(probabilities)) * 100
    )

    return probabilities


# ============================================================
# ROOT
# ============================================================

@app.route(
    "/",
    methods=["GET"]
)
def index():

    model_size = get_model_input_size()

    return jsonify({

        "success":
            True,

        "service":
            "Paddy Classification",

        "architecture":
            "ResNet50",

        "model":
            "best_paddy_resnet50.keras",

        "input_size":
            f"{model_size[0]}x{model_size[1]}",

        "classes":
            CLASSES,

        "total_classes":
            len(CLASSES),

        "model_type":
            "TensorFlow Keras",

        "preprocessing":
            "ResNet50 preprocess_input",

        "health":
            "/health",

        "model_status":
            "/model-status",

        "prediction":
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

    return jsonify({

        "success":
            True,

        "status":
            "healthy",

        "model":
            "best_paddy_resnet50.keras",

        "classes":
            CLASSES,

        "model_path":
            MODEL_PATH,

        "model_exists":
            os.path.isfile(
                MODEL_PATH
            ),

        "class_names_path":
            JSON_PATH,

        "class_names_exists":
            os.path.isfile(
                JSON_PATH
            ),

        "preprocessing":
            "ResNet50 preprocess_input"

    })


# ============================================================
# MODEL STATUS
# ============================================================

@app.route(
    "/model-status",
    methods=["GET"]
)
def model_status():

    try:

        model = get_model()

        return jsonify({

            "success":
                True,

            "model_loaded":
                True,

            "model_path":
                MODEL_PATH,

            "model_name":
                model.name,

            "input_shape":
                str(
                    model.input_shape
                ),

            "output_shape":
                str(
                    model.output_shape
                ),

            "classes":
                CLASSES,

            "total_classes":
                len(CLASSES)

        })

    except Exception as e:

        print(
            traceback.format_exc()
        )

        return jsonify({

            "success":
                False,

            "model_loaded":
                False,

            "error":
                str(e)

        }), 500


# ============================================================
# PREDICT
# ============================================================

@app.route(
    "/predict",
    methods=["POST"]
)
def predict():

    # ========================================================
    # CHECK IMAGE
    # ========================================================

    if "image" not in request.files:

        return jsonify({

            "success":
                False,

            "error":
                "No image file provided."

        }), 400


    file = request.files[
        "image"
    ]


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


    if len(file_bytes) > MAX_IMAGE_BYTES:

        return jsonify({

            "success":
                False,

            "error":
                "Image larger than 5MB."

        }), 400


    # ========================================================
    # IMAGE HASH
    # ========================================================

    image_hash = hashlib.md5(
        file_bytes
    ).hexdigest()


    try:

        print()
        print()
        print(
            "================================================"
        )

        print(
            "NEW PADDY PREDICTION"
        )

        print(
            "================================================"
        )

        print(
            "Filename:",
            file.filename
        )

        print(
            "File size:",
            len(file_bytes)
        )

        print(
            "IMAGE MD5:",
            image_hash
        )


        # ====================================================
        # PREPROCESS IMAGE
        # ====================================================

        input_data = (
            preprocess_image_bytes(
                file_bytes
            )
        )


        # ====================================================
        # TENSOR
        # ====================================================

        input_tensor = (
            tf.convert_to_tensor(
                input_data,
                dtype=tf.float32
            )
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
        # INFERENCE
        # ====================================================

        outputs = run_inference(
            input_tensor
        )


        raw_output = extract_raw_output(
            outputs
        )


        # ====================================================
        # CHECK CLASS COUNT
        # ====================================================

        if (
            len(raw_output)
            !=
            len(CLASSES)
        ):

            return jsonify({

                "success":
                    False,

                "error":
                    "Model output class count mismatch.",

                "model_output_classes":
                    len(raw_output),

                "class_names_count":
                    len(CLASSES),

                "class_names":
                    CLASSES,

                "raw_output":
                    raw_output.tolist(),

                "image_md5":
                    image_hash

            }), 500


        # ====================================================
        # PROBABILITIES
        # ====================================================

        probabilities = (
            convert_to_probabilities(
                raw_output
            )
        )


        # ====================================================
        # RESULT
        # ====================================================

        top_index = int(
            np.argmax(
                probabilities
            )
        )


        confidence = float(
            probabilities[
                top_index
            ]
        )


        variety_name = (
            CLASSES[
                top_index
            ]
        )


        # ====================================================
        # ALL PREDICTIONS
        # ====================================================

        predictions_map = {}


        for index, probability in enumerate(
            probabilities
        ):

            predictions_map[
                CLASSES[index]
            ] = round(
                float(probability)
                * 100,
                2
            )


        sorted_predictions = dict(
            sorted(
                predictions_map.items(),
                key=lambda item:
                    item[1],
                reverse=True
            )
        )


        # ====================================================
        # LOG RESULT
        # ====================================================

        print()
        print(
            "========== FINAL RESULT =========="
        )

        print(
            "IMAGE MD5:",
            image_hash
        )

        print(
            "CLASS INDEX:",
            top_index
        )

        print(
            "VARIETY:",
            variety_name
        )

        print(
            "CONFIDENCE:",
            round(
                confidence * 100,
                2
            )
        )

        print(
            "SORTED RESULTS:"
        )

        print(
            sorted_predictions
        )

        print(
            "=================================="
        )

        print()


        # ====================================================
        # API RESPONSE
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
                predictions_map,

            "sorted_predictions":
                sorted_predictions,

            "image_md5":
                image_hash,

            "raw_output":
                [
                    round(
                        float(x),
                        8
                    )
                    for x in raw_output
                ]

        })


    except UnidentifiedImageError:

        return jsonify({

            "success":
                False,

            "error":
                "Uploaded file is not a valid image.",

            "image_md5":
                image_hash

        }), 400


    except Exception as e:

        print()
        print(
            "========== SERVER ERROR =========="
        )

        print(
            "Type:",
            type(e).__name__
        )

        print(
            "Error:",
            str(e)
        )

        print(
            traceback.format_exc()
        )

        print(
            "=================================="
        )


        return jsonify({

            "success":
                False,

            "error":
                f"Inference error: {str(e)}",

            "image_md5":
                image_hash

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

    print(
        f"Starting server on port {port}"
    )

    app.run(
        host="0.0.0.0",
        port=port,
        debug=False
    )
