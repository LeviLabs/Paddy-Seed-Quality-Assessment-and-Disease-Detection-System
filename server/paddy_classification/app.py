import io
import os
import json
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
from tensorflow.keras.applications.convnext import preprocess_input


# ============================================================
# FLASK APP
# ============================================================

app = Flask(__name__)
CORS(app)


# ============================================================
# BASE PATHS
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
# DEBUG PATHS
# ============================================================

print()
print("================================================")
print("PADDY CLASSIFICATION SERVER STARTING")
print("================================================")

print(
    "BASE_DIR:",
    BASE_DIR
)

print(
    "MODEL_DIR:",
    MODEL_DIR
)

print(
    "SAVED_MODEL_PATH:",
    SAVED_MODEL_PATH
)

print(
    "SAVED MODEL EXISTS:",
    os.path.isdir(SAVED_MODEL_PATH)
)

print(
    "CLASS JSON:",
    JSON_PATH
)

print(
    "CLASS JSON EXISTS:",
    os.path.isfile(JSON_PATH)
)

print(
    "CONFIG:",
    CONFIG_PATH
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

            # ----------------------------------------
            # Format:
            #
            # [
            #   "Aumithri",
            #   "Bpt",
            #   ...
            # ]
            # ----------------------------------------

            if isinstance(data, list):

                print(
                    "Class names loaded from list."
                )

                return data

            # ----------------------------------------
            # Format:
            #
            # {
            #   "0": "Aumithri",
            #   "1": "Bpt"
            # }
            # ----------------------------------------

            if isinstance(data, dict):

                try:

                    classes = [
                        data[str(i)]
                        for i in range(len(data))
                    ]

                    print(
                        "Class names loaded from indexed dictionary."
                    )

                    return classes

                except Exception:

                    classes = list(
                        data.values()
                    )

                    print(
                        "Class names loaded from dictionary values."
                    )

                    return classes

        except Exception as e:

            print(
                "ERROR loading class_names.json:",
                str(e)
            )

    print(
        "Using DEFAULT_CLASSES."
    )

    return DEFAULT_CLASSES


CLASSES = load_class_names()


print(
    f"Loaded {len(CLASSES)} classes:"
)

print(
    CLASSES
)


# ============================================================
# SAVED MODEL VARIABLES
# ============================================================

_model = None
_model_infer_fn = None
_model_input_name = None


# ============================================================
# LOAD SAVED MODEL
# ============================================================

def get_infer_fn():

    global _model
    global _model_infer_fn
    global _model_input_name

    if _model_infer_fn is None:

        print()
        print(
            "================================================"
        )

        print(
            "LOADING PADDY SAVED MODEL"
        )

        print(
            "================================================"
        )

        print(
            "Model path:",
            SAVED_MODEL_PATH
        )

        print(
            "Model folder exists:",
            os.path.isdir(SAVED_MODEL_PATH)
        )

        # ====================================================
        # CHECK FOLDER
        # ====================================================

        if not os.path.isdir(SAVED_MODEL_PATH):

            raise FileNotFoundError(
                f"SavedModel directory not found: "
                f"{SAVED_MODEL_PATH}"
            )

        # ====================================================
        # CHECK saved_model.pb
        # ====================================================

        saved_model_pb = os.path.join(
            SAVED_MODEL_PATH,
            "saved_model.pb"
        )

        print(
            "saved_model.pb:",
            saved_model_pb
        )

        print(
            "saved_model.pb exists:",
            os.path.isfile(saved_model_pb)
        )

        if not os.path.isfile(saved_model_pb):

            raise FileNotFoundError(
                f"saved_model.pb not found inside: "
                f"{SAVED_MODEL_PATH}"
            )

        # ====================================================
        # LOAD MODEL
        # ====================================================

        print(
            "Loading TensorFlow SavedModel..."
        )

        _model = tf.saved_model.load(
            SAVED_MODEL_PATH
        )

        print(
            "TensorFlow SavedModel loaded."
        )

        # ====================================================
        # GET SIGNATURES
        # ====================================================

        signatures = list(
            _model.signatures.keys()
        )

        print(
            "Available signatures:",
            signatures
        )

        if "serving_default" not in _model.signatures:

            raise RuntimeError(
                "SavedModel does not contain "
                "'serving_default' signature. "
                f"Available signatures: {signatures}"
            )

        _model_infer_fn = (
            _model.signatures[
                "serving_default"
            ]
        )

        # ====================================================
        # PRINT INPUT SIGNATURE
        # ====================================================

        print(
            "Structured input signature:"
        )

        print(
            _model_infer_fn.structured_input_signature
        )

        print(
            "Structured outputs:"
        )

        print(
            _model_infer_fn.structured_outputs
        )

        # ====================================================
        # DETECT INPUT NAME
        # ====================================================

        args_signature, kwargs_signature = (
            _model_infer_fn.structured_input_signature
        )

        if kwargs_signature:

            _model_input_name = list(
                kwargs_signature.keys()
            )[0]

            print(
                "Detected model input name:",
                _model_input_name
            )

        else:

            _model_input_name = None

            print(
                "Model appears to use positional input."
            )

        print(
            "================================================"
        )

        print(
            "MODEL LOADED SUCCESSFULLY"
        )

        print(
            "================================================"
        )

        print()

    return _model_infer_fn


# ============================================================
# IMAGE LIMIT
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

    # ========================================================
    # OPEN IMAGE
    # ========================================================

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

    # ========================================================
    # RGB
    # ========================================================

    image = image.convert(
        "RGB"
    )

    # ========================================================
    # RESIZE
    # ========================================================

    image = image.resize(
        target_size,
        Image.Resampling.BILINEAR
    )

    # ========================================================
    # NUMPY ARRAY
    # ========================================================

    img_array = np.asarray(
        image,
        dtype=np.float32
    )

    print(
        "Before preprocessing min:",
        float(
            np.min(img_array)
        )
    )

    print(
        "Before preprocessing max:",
        float(
            np.max(img_array)
        )
    )

    # ========================================================
    # ADD BATCH DIMENSION
    # ========================================================

    img_array = np.expand_dims(
        img_array,
        axis=0
    )

    # ========================================================
    # CONVNEXT PREPROCESSING
    # ========================================================

    img_array = preprocess_input(
        img_array
    )

    print(
        "After preprocessing min:",
        float(
            np.min(img_array)
        )
    )

    print(
        "After preprocessing max:",
        float(
            np.max(img_array)
        )
    )

    print(
        "Final image shape:",
        img_array.shape
    )

    return img_array


# ============================================================
# RUN MODEL INFERENCE
# ============================================================

def run_inference(
    input_tensor
):

    global _model_input_name

    infer_fn = get_infer_fn()

    print(
        "Running SavedModel inference..."
    )

    # ========================================================
    # NAMED INPUT
    # ========================================================

    if _model_input_name:

        print(
            "Using named input:",
            _model_input_name
        )

        predictions_dict = infer_fn(
            **{
                _model_input_name:
                    input_tensor
            }
        )

    # ========================================================
    # POSITIONAL INPUT
    # ========================================================

    else:

        predictions_dict = infer_fn(
            input_tensor
        )

    return predictions_dict


# ============================================================
# EXTRACT OUTPUT
# ============================================================

def extract_raw_output(
    predictions_dict
):

    print()
    print(
        "========== MODEL OUTPUT =========="
    )

    # ========================================================
    # DICTIONARY OUTPUT
    # ========================================================

    if isinstance(
        predictions_dict,
        dict
    ):

        output_keys = list(
            predictions_dict.keys()
        )

        print(
            "Output keys:",
            output_keys
        )

        if not output_keys:

            raise RuntimeError(
                "Model returned an empty output dictionary."
            )

        output_key = output_keys[0]

        output_tensor = (
            predictions_dict[
                output_key
            ]
        )

        print(
            "Selected output key:",
            output_key
        )

    # ========================================================
    # TENSOR OUTPUT
    # ========================================================

    else:

        output_tensor = predictions_dict

    # ========================================================
    # TENSOR -> NUMPY
    # ========================================================

    if tf.is_tensor(
        output_tensor
    ):

        print(
            "Output tensor shape:",
            output_tensor.shape
        )

        output_array = (
            output_tensor.numpy()
        )

    else:

        output_array = np.asarray(
            output_tensor
        )

    print(
        "Output array shape:",
        output_array.shape
    )

    # ========================================================
    # REMOVE BATCH
    # ========================================================

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
        "Raw output:",
        raw_output
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

    # ========================================================
    # CLEAN VALUES
    # ========================================================

    values = np.nan_to_num(
        values,
        nan=0.0,
        posinf=0.0,
        neginf=0.0
    )

    output_sum = float(
        np.sum(values)
    )

    output_min = float(
        np.min(values)
    )

    output_max = float(
        np.max(values)
    )

    print(
        "Raw output sum:",
        output_sum
    )

    print(
        "Raw output min:",
        output_min
    )

    print(
        "Raw output max:",
        output_max
    )

    # ========================================================
    # ALREADY PROBABILITIES
    # ========================================================

    if (
        np.all(values >= 0)
        and
        np.all(values <= 1.0)
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

    # ========================================================
    # LOGITS
    # ========================================================

    else:

        print(
            "Output detected as logits."
        )

        print(
            "Applying softmax..."
        )

        probabilities = (
            tf.nn.softmax(
                values
            ).numpy()
        )

    return probabilities


# ============================================================
# ROOT ENDPOINT
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
            "Paddy ConvNeXt-Tiny Classification",

        "architecture":
            "ConvNeXt-Tiny",

        "input_size":
            "320x320",

        "total_classes":
            len(CLASSES),

        "classes":
            CLASSES,

        "model_type":
            "TensorFlow SavedModel",

        "saved_model_path":
            SAVED_MODEL_PATH,

        "model_exists":
            os.path.isdir(
                SAVED_MODEL_PATH
            ),

        "prediction_endpoint":
            "POST /predict",

        "health_endpoint":
            "GET /health",

        "model_status_endpoint":
            "GET /model-status"

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

        "service":
            "paddy_classification",

        "architecture":
            "ConvNeXt-Tiny",

        "input_size":
            "320x320",

        "total_classes":
            len(CLASSES),

        "classes":
            CLASSES,

        "model_path":
            SAVED_MODEL_PATH,

        "model_folder_exists":
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

        "config_exists":
            os.path.isfile(
                CONFIG_PATH
            )

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

            "model_folder_exists":
                os.path.isdir(
                    SAVED_MODEL_PATH
                ),

            "model_path":
                SAVED_MODEL_PATH,

            "input_signature":
                str(
                    infer_fn
                    .structured_input_signature
                ),

            "outputs":
                str(
                    infer_fn
                    .structured_outputs
                ),

            "classes":
                CLASSES

        })

    except Exception as e:

        print(
            "MODEL STATUS ERROR:"
        )

        print(
            traceback.format_exc()
        )

        return jsonify({

            "success":
                False,

            "model_loaded":
                False,

            "model_folder_exists":
                os.path.isdir(
                    SAVED_MODEL_PATH
                ),

            "model_path":
                SAVED_MODEL_PATH,

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
    # IMAGE FIELD
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


    # ========================================================
    # FILENAME
    # ========================================================

    if file.filename == "":

        return jsonify({

            "success":
                False,

            "error":
                "Empty filename."

        }), 400


    # ========================================================
    # READ IMAGE
    # ========================================================

    file_bytes = file.read()


    if not file_bytes:

        return jsonify({

            "success":
                False,

            "error":
                "Image file is empty."

        }), 400


    # ========================================================
    # SIZE LIMIT
    # ========================================================

    if (
        len(file_bytes)
        >
        MAX_IMAGE_BYTES
    ):

        return jsonify({

            "success":
                False,

            "error":
                (
                    "Image too large. "
                    "Maximum size is 5MB. "
                    f"Uploaded: "
                    f"{len(file_bytes) // 1024} KB."
                )

        }), 400


    try:

        print()
        print(
            "================================================"
        )

        print(
            "NEW PADDY CLASSIFICATION REQUEST"
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
            len(file_bytes),
            "bytes"
        )

        # ====================================================
        # PREPROCESS
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

        predictions_dict = (
            run_inference(
                input_tensor
            )
        )

        # ====================================================
        # GET OUTPUT
        # ====================================================

        raw_output = (
            extract_raw_output(
                predictions_dict
            )
        )

        # ====================================================
        # CHECK OUTPUT SIZE
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
                    (
                        "Model output class count does not "
                        "match class_names.json."
                    ),

                "model_output_classes":
                    len(
                        raw_output
                    ),

                "class_names_count":
                    len(
                        CLASSES
                    ),

                "raw_output":
                    raw_output.tolist()

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
        # TOP CLASS
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

        if (
            top_index
            <
            len(CLASSES)
        ):

            variety_name = (
                CLASSES[
                    top_index
                ]
            )

        else:

            variety_name = (
                "Unknown"
            )

        # ====================================================
        # ALL PREDICTIONS
        # ====================================================

        predictions_map = {}

        for idx, prob in enumerate(
            probabilities
        ):

            if idx < len(CLASSES):

                class_name = (
                    CLASSES[idx]
                )

            else:

                class_name = (
                    f"class_{idx}"
                )

            predictions_map[
                class_name
            ] = round(
                float(prob) * 100,
                2
            )

        # ====================================================
        # SORT FOR LOGS
        # ====================================================

        sorted_predictions = sorted(
            predictions_map.items(),
            key=lambda x: x[1],
            reverse=True
        )

        # ====================================================
        # LOG FINAL RESULT
        # ====================================================

        print()
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
            "All predictions:"
        )

        for (
            class_name,
            probability
        ) in sorted_predictions:

            print(
                f"{class_name}: "
                f"{probability}%"
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
    # MISSING MODEL
    # ========================================================

    except FileNotFoundError as e:

        print()
        print(
            "MODEL FILE ERROR"
        )

        print(
            str(e)
        )

        return jsonify({

            "success":
                False,

            "error":
                str(e),

            "model_path":
                SAVED_MODEL_PATH,

            "model_exists":
                os.path.isdir(
                    SAVED_MODEL_PATH
                )

        }), 500


    # ========================================================
    # GENERAL ERROR
    # ========================================================

    except Exception as e:

        print()
        print(
            "========== PREDICTION ERROR =========="
        )

        print(
            "Error type:",
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
            "======================================"
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
    print(
        "================================================"
    )

    print(
        "STARTING PADDY CLASSIFICATION SERVER"
    )

    print(
        f"Port: {port}"
    )

    print(
        "================================================"
    )

    app.run(
        host="0.0.0.0",
        port=port,
        debug=False
    )
