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

SAVED_MODEL_PATH = os.path.join(
    MODEL_DIR,
    "saved_model"
)

JSON_PATH = os.path.join(
    MODEL_DIR,
    "class_names.json"
)

CONFIG_PATH = os.path.join(
    MODEL_DIR,
    "model_config.json"
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

print("SAVED_MODEL_PATH:")
print(SAVED_MODEL_PATH)

print(
    "MODEL DIRECTORY EXISTS:",
    os.path.isdir(SAVED_MODEL_PATH)
)

print(
    "CLASS JSON EXISTS:",
    os.path.isfile(JSON_PATH)
)

print(
    "CONFIG EXISTS:",
    os.path.isfile(CONFIG_PATH)
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

            if isinstance(data, list):

                return data

            if isinstance(data, dict):

                try:

                    return [
                        data[str(i)]
                        for i in range(len(data))
                    ]

                except Exception:

                    return list(
                        data.values()
                    )

        except Exception as e:

            print(
                "CLASS JSON ERROR:",
                str(e)
            )

    print(
        "Using DEFAULT_CLASSES."
    )

    return DEFAULT_CLASSES


CLASSES = load_class_names()


print(
    "Loaded classes:",
    CLASSES
)


# ============================================================
# MODEL GLOBAL VARIABLES
# ============================================================

_model = None
_infer_fn = None
_input_name = None


# ============================================================
# LOAD SAVED MODEL
# ============================================================

def get_infer_fn():

    global _model
    global _infer_fn
    global _input_name

    if _infer_fn is not None:
        return _infer_fn

    print()
    print("================================================")
    print("LOADING SAVED MODEL")
    print("================================================")

    print(
        "Path:",
        SAVED_MODEL_PATH
    )

    if not os.path.isdir(
        SAVED_MODEL_PATH
    ):

        raise FileNotFoundError(
            f"SavedModel directory not found: "
            f"{SAVED_MODEL_PATH}"
        )

    saved_model_pb = os.path.join(
        SAVED_MODEL_PATH,
        "saved_model.pb"
    )

    if not os.path.isfile(
        saved_model_pb
    ):

        raise FileNotFoundError(
            f"saved_model.pb not found: "
            f"{saved_model_pb}"
        )

    print(
        "Loading TensorFlow SavedModel..."
    )

    _model = tf.saved_model.load(
        SAVED_MODEL_PATH
    )

    print(
        "SavedModel loaded successfully."
    )

    signatures = list(
        _model.signatures.keys()
    )

    print(
        "Available signatures:",
        signatures
    )

    if (
        "serving_default"
        not in
        _model.signatures
    ):

        raise RuntimeError(
            "serving_default signature not found. "
            f"Available signatures: {signatures}"
        )

    _infer_fn = (
        _model.signatures[
            "serving_default"
        ]
    )

    print(
        "Input signature:"
    )

    print(
        _infer_fn
        .structured_input_signature
    )

    print(
        "Output signature:"
    )

    print(
        _infer_fn
        .structured_outputs
    )

    args_signature, kwargs_signature = (
        _infer_fn
        .structured_input_signature
    )

    if kwargs_signature:

        _input_name = list(
            kwargs_signature.keys()
        )[0]

        print(
            "Detected input name:",
            _input_name
        )

    else:

        _input_name = None

        print(
            "Using positional model input."
        )

    print("================================================")
    print("MODEL READY")
    print("================================================")
    print()

    return _infer_fn


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
        "Image min:",
        float(
            np.min(img_array)
        )
    )

    print(
        "Image max:",
        float(
            np.max(img_array)
        )
    )

    print(
        "Image mean:",
        float(
            np.mean(img_array)
        )
    )

    # ========================================================
    # IMPORTANT TEST
    #
    # NO ConvNeXt preprocess_input() here.
    #
    # We are testing whether the model already contains
    # preprocessing internally.
    # ========================================================

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

    return img_array


# ============================================================
# RUN MODEL
# ============================================================

def run_inference(
    input_tensor
):

    global _input_name

    infer_fn = get_infer_fn()

    print(
        "Running inference..."
    )

    if _input_name:

        outputs = infer_fn(
            **{
                _input_name:
                    input_tensor
            }
        )

    else:

        outputs = infer_fn(
            input_tensor
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

    if isinstance(
        outputs,
        dict
    ):

        keys = list(
            outputs.keys()
        )

        print(
            "Output keys:",
            keys
        )

        if not keys:

            raise RuntimeError(
                "Model returned an empty dictionary."
            )

        output_key = keys[0]

        output_tensor = outputs[
            output_key
        ]

        print(
            "Using output key:",
            output_key
        )

    else:

        output_tensor = outputs

    if tf.is_tensor(
        output_tensor
    ):

        output_array = (
            output_tensor.numpy()
        )

    else:

        output_array = np.asarray(
            output_tensor
        )

    print(
        "Full output shape:",
        output_array.shape
    )

    if output_array.ndim > 1:

        raw_output = (
            output_array[0]
        )

    else:

        raw_output = (
            output_array
        )

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
        int(
            np.argmax(raw_output)
        )
    )

    print(
        "RAW SUM:",
        float(
            np.sum(raw_output)
        )
    )

    print(
        "RAW MIN:",
        float(
            np.min(raw_output)
        )
    )

    print(
        "RAW MAX:",
        float(
            np.max(raw_output)
        )
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
    # ALREADY PROBABILITIES
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
    # LOGITS
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
        int(
            np.argmax(probabilities)
        )
    )

    print(
        "FINAL MAX CONFIDENCE:",
        float(
            np.max(probabilities)
        )
        * 100
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

    return jsonify({

        "success":
            True,

        "service":
            "Paddy Classification",

        "architecture":
            "ConvNeXt-Tiny",

        "input_size":
            "320x320",

        "classes":
            CLASSES,

        "total_classes":
            len(CLASSES),

        "model_type":
            "TensorFlow SavedModel",

        "preprocessing":
            "RGB float32 0-255 - no external preprocess_input",

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

    saved_model_pb = os.path.join(
        SAVED_MODEL_PATH,
        "saved_model.pb"
    )

    return jsonify({

        "success":
            True,

        "status":
            "healthy",

        "classes":
            CLASSES,

        "model_directory":
            SAVED_MODEL_PATH,

        "model_directory_exists":
            os.path.isdir(
                SAVED_MODEL_PATH
            ),

        "saved_model_pb_exists":
            os.path.isfile(
                saved_model_pb
            ),

        "class_names_exists":
            os.path.isfile(
                JSON_PATH
            ),

        "preprocessing":
            "NO external ConvNeXt preprocess_input"

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

        infer_fn = get_infer_fn()

        return jsonify({

            "success":
                True,

            "model_loaded":
                True,

            "model_path":
                SAVED_MODEL_PATH,

            "input_signature":
                str(
                    infer_fn
                    .structured_input_signature
                ),

            "output_signature":
                str(
                    infer_fn
                    .structured_outputs
                ),

            "classes":
                CLASSES

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
                file_bytes,
                target_size=(
                    320,
                    320
                )
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

            # Diagnostic information
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
