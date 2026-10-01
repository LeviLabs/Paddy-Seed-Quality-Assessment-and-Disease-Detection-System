import io
import os
import json

# ============================================================
# TENSORFLOW SETTINGS
# ============================================================

os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'


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
    'models'
)

MODEL_PATH = os.path.join(
    MODEL_DIR,
    'paddy_convnext_tiny.keras'
)

JSON_PATH = os.path.join(
    MODEL_DIR,
    'class_names.json'
)

CONFIG_PATH = os.path.join(
    MODEL_DIR,
    'model_config.json'
)


# ============================================================
# DEBUG PATHS
# ============================================================

print()
print("==============================================")
print("PADDY CLASSIFICATION SERVER")
print("==============================================")

print(
    "BASE_DIR:",
    BASE_DIR
)

print(
    "MODEL_DIR:",
    MODEL_DIR
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
    "CLASS JSON PATH:",
    JSON_PATH
)

print(
    "CLASS JSON EXISTS:",
    os.path.isfile(JSON_PATH)
)

print(
    "CONFIG PATH:",
    CONFIG_PATH
)

print(
    "CONFIG EXISTS:",
    os.path.isfile(CONFIG_PATH)
)

print("==============================================")
print()


# ============================================================
# DEFAULT CLASSES
# ============================================================

DEFAULT_CLASSES = [
    'Aumithri',
    'Bpt',
    'Hmt',
    'Ir_64',
    'Mota_Mahamaya',
    'Mota_Paan',
    'Rb_Gold',
    'Sarna'
]


# ============================================================
# LOAD CLASS NAMES
# ============================================================

def load_class_names():

    if os.path.isfile(JSON_PATH):

        try:

            with open(
                JSON_PATH,
                'r',
                encoding='utf-8'
            ) as f:

                data = json.load(f)

            # --------------------------------------------
            # JSON format:
            #
            # [
            #   "Aumithri",
            #   "Bpt",
            #   ...
            # ]
            # --------------------------------------------

            if isinstance(data, list):

                return data

            # --------------------------------------------
            # JSON format:
            #
            # {
            #   "0": "Aumithri",
            #   "1": "Bpt",
            #   ...
            # }
            # --------------------------------------------

            elif isinstance(data, dict):

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
                f'Warning loading class names: {e}'
            )

    print(
        'Using DEFAULT_CLASSES because '
        'class_names.json could not be loaded.'
    )

    return DEFAULT_CLASSES


CLASSES = load_class_names()


print(
    f'Loaded {len(CLASSES)} paddy classes:'
)

print(
    CLASSES
)


# ============================================================
# LOAD MODEL
# ============================================================

_model = None


def get_model():

    global _model

    if _model is None:

        print()
        print(
            '=============================================='
        )

        print(
            'LOADING PADDY MODEL'
        )

        print(
            '=============================================='
        )

        print(
            f'Model path: {MODEL_PATH}'
        )

        # --------------------------------------------
        # Check model file
        # --------------------------------------------

        if not os.path.isfile(MODEL_PATH):

            raise FileNotFoundError(
                f'Model file not found: {MODEL_PATH}'
            )

        # --------------------------------------------
        # Load Keras model
        # --------------------------------------------

        _model = tf.keras.models.load_model(
            MODEL_PATH,
            compile=False
        )

        print(
            'Paddy ConvNeXt-Tiny model '
            'loaded successfully.'
        )

        # --------------------------------------------
        # Input shape
        # --------------------------------------------

        try:

            print(
                'Model input shape:',
                _model.input_shape
            )

        except Exception as e:

            print(
                'Unable to read input shape:',
                e
            )

        # --------------------------------------------
        # Output shape
        # --------------------------------------------

        try:

            print(
                'Model output shape:',
                _model.output_shape
            )

        except Exception as e:

            print(
                'Unable to read output shape:',
                e
            )

        print(
            '=============================================='
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

    # --------------------------------------------
    # Open image
    # --------------------------------------------

    image = Image.open(
        io.BytesIO(file_bytes)
    )

    print(
        'Original image size:',
        image.size
    )

    print(
        'Original image mode:',
        image.mode
    )

    # --------------------------------------------
    # Convert to RGB
    # --------------------------------------------

    image = image.convert(
        'RGB'
    )

    # --------------------------------------------
    # Resize
    # --------------------------------------------

    image = image.resize(
        target_size,
        Image.Resampling.BILINEAR
    )

    # --------------------------------------------
    # Convert to NumPy
    # --------------------------------------------

    img_array = np.asarray(
        image,
        dtype=np.float32
    )

    print(
        'Before ConvNeXt preprocessing:'
    )

    print(
        'Min:',
        float(np.min(img_array))
    )

    print(
        'Max:',
        float(np.max(img_array))
    )

    # --------------------------------------------
    # Add batch dimension
    #
    # (320,320,3)
    #
    # becomes
    #
    # (1,320,320,3)
    # --------------------------------------------

    img_array = np.expand_dims(
        img_array,
        axis=0
    )

    # --------------------------------------------
    # ConvNeXt preprocessing
    # --------------------------------------------

    img_array = preprocess_input(
        img_array
    )

    print(
        'After ConvNeXt preprocessing:'
    )

    print(
        'Min:',
        float(np.min(img_array))
    )

    print(
        'Max:',
        float(np.max(img_array))
    )

    print(
        'Final input shape:',
        img_array.shape
    )

    return img_array


# ============================================================
# CONVERT OUTPUT TO NUMPY
# ============================================================

def extract_model_output(
    predictions
):

    # --------------------------------------------
    # If model returns dictionary
    # --------------------------------------------

    if isinstance(
        predictions,
        dict
    ):

        print(
            'Model returned dictionary.'
        )

        print(
            'Output keys:',
            list(predictions.keys())
        )

        first_key = list(
            predictions.keys()
        )[0]

        predictions = predictions[
            first_key
        ]

    # --------------------------------------------
    # If model returns list
    # --------------------------------------------

    elif isinstance(
        predictions,
        (list, tuple)
    ):

        print(
            'Model returned list/tuple.'
        )

        predictions = predictions[0]

    # --------------------------------------------
    # Tensor -> NumPy
    # --------------------------------------------

    if tf.is_tensor(
        predictions
    ):

        predictions = predictions.numpy()

    # --------------------------------------------
    # Convert to NumPy
    # --------------------------------------------

    predictions = np.asarray(
        predictions
    )

    print(
        'Prediction array shape:',
        predictions.shape
    )

    # --------------------------------------------
    # Remove batch dimension
    # --------------------------------------------

    if predictions.ndim > 1:

        predictions = predictions[0]

    return predictions


# ============================================================
# CONVERT MODEL OUTPUT TO PROBABILITIES
# ============================================================

def convert_to_probabilities(
    raw_output
):

    values = np.asarray(
        raw_output,
        dtype=np.float32
    )

    # --------------------------------------------
    # Replace NaN / Inf
    # --------------------------------------------

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
        'Raw output sum:',
        output_sum
    )

    print(
        'Raw output min:',
        output_min
    )

    print(
        'Raw output max:',
        output_max
    )

    # ====================================================
    # CASE 1
    #
    # Already probabilities
    # ====================================================

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
            'Output detected as probabilities.'
        )

        probabilities = values

    # ====================================================
    # CASE 2
    #
    # Logits -> Softmax
    # ====================================================

    else:

        print(
            'Output detected as logits.'
        )

        print(
            'Applying softmax.'
        )

        probabilities = tf.nn.softmax(
            values
        ).numpy()

    return probabilities


# ============================================================
# ROOT ENDPOINT
# ============================================================

@app.route(
    '/',
    methods=['GET']
)
def index():

    return jsonify({

        'success':
            True,

        'service':
            'Paddy ConvNeXt-Tiny Classification',

        'architecture':
            'ConvNeXt-Tiny',

        'input_size':
            '320x320',

        'classes':
            CLASSES,

        'total_classes':
            len(CLASSES),

        'model_file':
            'paddy_convnext_tiny.keras',

        'model_exists':
            os.path.isfile(
                MODEL_PATH
            ),

        'endpoint':
            'POST /predict'

    })


# ============================================================
# HEALTH ENDPOINT
# ============================================================

@app.route(
    '/health',
    methods=['GET']
)
def health():

    return jsonify({

        'success':
            True,

        'status':
            'healthy',

        'service':
            'paddy_classification',

        'architecture':
            'ConvNeXt-Tiny',

        'input_size':
            '320x320',

        'classes':
            CLASSES,

        'total_classes':
            len(CLASSES),

        'model_path':
            MODEL_PATH,

        'model_exists':
            os.path.isfile(
                MODEL_PATH
            ),

        'class_names_path':
            JSON_PATH,

        'class_names_exists':
            os.path.isfile(
                JSON_PATH
            )

    })


# ============================================================
# PREDICTION ENDPOINT
# ============================================================

@app.route(
    '/predict',
    methods=['POST']
)
def predict():

    # ========================================================
    # CHECK IMAGE
    # ========================================================

    if 'image' not in request.files:

        return jsonify({

            'success':
                False,

            'error':
                'No image file provided.'

        }), 400


    file = request.files[
        'image'
    ]


    # ========================================================
    # CHECK FILENAME
    # ========================================================

    if file.filename == '':

        return jsonify({

            'success':
                False,

            'error':
                'Empty filename.'

        }), 400


    # ========================================================
    # READ IMAGE
    # ========================================================

    file_bytes = file.read()


    if not file_bytes:

        return jsonify({

            'success':
                False,

            'error':
                'Image file is empty.'

        }), 400


    # ========================================================
    # IMAGE SIZE LIMIT
    # ========================================================

    if len(file_bytes) > MAX_IMAGE_BYTES:

        return jsonify({

            'success':
                False,

            'error':
                (
                    'Image too large. '
                    'Maximum size is 5MB. '
                    f'Uploaded size: '
                    f'{len(file_bytes) // 1024}KB.'
                )

        }), 400


    try:

        print()
        print(
            '=============================================='
        )

        print(
            'NEW PADDY CLASSIFICATION REQUEST'
        )

        print(
            '=============================================='
        )

        print(
            'Filename:',
            file.filename
        )

        print(
            'Image bytes:',
            len(file_bytes)
        )


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
            'Tensor shape:',
            input_tensor.shape
        )

        print(
            'Tensor dtype:',
            input_tensor.dtype
        )


        # ====================================================
        # MODEL INFERENCE
        # ====================================================

        print()
        print(
            'Running model inference...'
        )

        predictions = model(
            input_tensor,
            training=False
        )


        # ====================================================
        # EXTRACT OUTPUT
        # ====================================================

        raw_output = extract_model_output(
            predictions
        )


        # ====================================================
        # DEBUG OUTPUT
        # ====================================================

        print()
        print(
            '========== MODEL OUTPUT DEBUG =========='
        )

        print(
            'Output shape:',
            raw_output.shape
        )

        print(
            'Raw output:',
            raw_output
        )

        print(
            '========================================='
        )


        # ====================================================
        # CHECK OUTPUT SIZE
        # ====================================================

        if len(raw_output) != len(CLASSES):

            return jsonify({

                'success':
                    False,

                'error':
                    (
                        'Model output class count does not '
                        'match class_names.json.'
                    ),

                'model_output_classes':
                    len(raw_output),

                'class_names_count':
                    len(CLASSES),

                'model_output':
                    raw_output.tolist()

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
            np.argmax(
                probabilities
            )
        )


        confidence = float(
            probabilities[
                top_index
            ]
        )


        if top_index < len(CLASSES):

            variety_name = CLASSES[
                top_index
            ]

        else:

            variety_name = 'Unknown'


        # ====================================================
        # ALL PREDICTIONS
        # ====================================================

        predictions_map = {}


        for idx, prob in enumerate(
            probabilities
        ):

            if idx < len(CLASSES):

                cls_name = CLASSES[
                    idx
                ]

            else:

                cls_name = (
                    f'class_{idx}'
                )


            predictions_map[
                cls_name
            ] = round(
                float(prob) * 100,
                2
            )


        # ====================================================
        # SORT PREDICTIONS
        # ====================================================

        sorted_predictions = sorted(
            predictions_map.items(),
            key=lambda x: x[1],
            reverse=True
        )


        print()
        print(
            '========== FINAL PREDICTION =========='
        )

        print(
            'Predicted variety:',
            variety_name
        )

        print(
            'Confidence:',
            round(
                confidence * 100,
                2
            ),
            '%'
        )

        print(
            'Class index:',
            top_index
        )

        print(
            'All predictions:'
        )

        for name, probability in sorted_predictions:

            print(
                f'{name}: {probability}%'
            )

        print(
            '======================================'
        )

        print()


        # ====================================================
        # RESPONSE
        # ====================================================

        return jsonify({

            'success':
                True,

            'variety':
                variety_name,

            'confidence':
                round(
                    confidence * 100,
                    2
                ),

            'class_index':
                top_index,

            'all_predictions':
                predictions_map

        })


    # ========================================================
    # INVALID IMAGE
    # ========================================================

    except UnidentifiedImageError:

        return jsonify({

            'success':
                False,

            'error':
                'Uploaded file is not a valid image.'

        }), 400


    # ========================================================
    # MODEL FILE MISSING
    # ========================================================

    except FileNotFoundError as e:

        print(
            'MODEL FILE ERROR:',
            str(e)
        )

        return jsonify({

            'success':
                False,

            'error':
                str(e),

            'model_path':
                MODEL_PATH,

            'model_exists':
                os.path.isfile(
                    MODEL_PATH
                )

        }), 500


    # ========================================================
    # GENERAL ERROR
    # ========================================================

    except Exception as e:

        print()
        print(
            '========== PREDICTION ERROR =========='
        )

        print(
            type(e).__name__
        )

        print(
            str(e)
        )

        print(
            '======================================'
        )

        return jsonify({

            'success':
                False,

            'error':
                f'Inference error: {str(e)}'

        }), 500


# ============================================================
# START SERVER
# ============================================================

if __name__ == '__main__':

    port = int(
        os.environ.get(
            'PORT',
            5000
        )
    )

    print(
        f'Starting server on port {port}'
    )

    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
