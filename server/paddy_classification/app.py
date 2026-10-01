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
# DEBUG PATH INFORMATION
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
# DEFAULT CLASS NAMES
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

            # =================================================
            # FORMAT 1
            #
            # [
            #   "Aumithri",
            #   "Bpt",
            #   ...
            # ]
            # =================================================

            if isinstance(data, list):

                return data

            # =================================================
            # FORMAT 2
            #
            # {
            #   "0": "Aumithri",
            #   "1": "Bpt",
            #   ...
            # }
            # =================================================

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
        'Using default class names.'
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
# GLOBAL MODEL VARIABLE
# ============================================================

_model = None


# ============================================================
# LOAD MODEL
# ============================================================

def get_model():

    global _model

    if _model is None:

        print()
        print(
            "=============================================="
        )

        print(
            "LOADING PADDY MODEL"
        )

        print(
            "=============================================="
        )

        print(
            f'Model path: {MODEL_PATH}'
        )

        # ====================================================
        # CHECK FILE
        # ====================================================

        if not os.path.isfile(MODEL_PATH):

            raise FileNotFoundError(
                f'Model file not found: {MODEL_PATH}'
            )

        # ====================================================
        # LOAD MODEL
        #
        # safe_mode=False is required because your model
        # contains a Lambda layer.
        # ====================================================

        try:

            _model = tf.keras.models.load_model(
                MODEL_PATH,
                compile=False,
                safe_mode=False
            )

        except TypeError as e:

            print(
                'safe_mode parameter not supported.'
            )

            print(
                'Trying unsafe deserialization fallback...'
            )

            try:

                import keras

                keras.config.enable_unsafe_deserialization()

                _model = tf.keras.models.load_model(
                    MODEL_PATH,
                    compile=False
                )

            except Exception:

                raise e

        # ====================================================
        # MODEL LOADED
        # ====================================================

        print(
            'Paddy ConvNeXt-Tiny model '
            'loaded successfully.'
        )

        # ====================================================
        # INPUT SHAPE
        # ====================================================

        try:

            print(
                'Model input shape:',
                _model.input_shape
            )

        except Exception as e:

            print(
                'Unable to read model input shape:',
                e
            )

        # ====================================================
        # OUTPUT SHAPE
        # ====================================================

        try:

            print(
                'Model output shape:',
                _model.output_shape
            )

        except Exception as e:

            print(
                'Unable to read model output shape:',
                e
            )

        print(
            "=============================================="
        )

        print()

    return _model


# ============================================================
# IMAGE SIZE LIMIT
# ============================================================

MAX_IMAGE_BYTES = 5 * 1024 * 1024


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
        'Original image size:',
        image.size
    )

    print(
        'Original image mode:',
        image.mode
    )


    # ========================================================
    # CONVERT RGB
    # ========================================================

    image = image.convert(
        'RGB'
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
        'Image min before preprocessing:',
        float(np.min(img_array))
    )

    print(
        'Image max before preprocessing:',
        float(np.max(img_array))
    )


    # ========================================================
    # ADD BATCH DIMENSION
    #
    # (320,320,3)
    #
    # ->
    #
    # (1,320,320,3)
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
        'Image min after preprocessing:',
        float(np.min(img_array))
    )

    print(
        'Image max after preprocessing:',
        float(np.max(img_array))
    )

    print(
        'Final input shape:',
        img_array.shape
    )


    return img_array


# ============================================================
# EXTRACT MODEL OUTPUT
# ============================================================

def extract_model_output(
    predictions
):

    # ========================================================
    # DICTIONARY OUTPUT
    # ========================================================

    if isinstance(
        predictions,
        dict
    ):

        print(
            'Model returned dictionary output.'
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


    # ========================================================
    # LIST / TUPLE OUTPUT
    # ========================================================

    elif isinstance(
        predictions,
        (list, tuple)
    ):

        print(
            'Model returned list/tuple output.'
        )

        predictions = predictions[0]


    # ========================================================
    # TENSOR -> NUMPY
    # ========================================================

    if tf.is_tensor(
        predictions
    ):

        predictions = predictions.numpy()


    predictions = np.asarray(
        predictions
    )


    print(
        'Prediction output shape:',
        predictions.shape
    )


    # ========================================================
    # REMOVE BATCH DIMENSION
    # ========================================================

    if predictions.ndim > 1:

        predictions = predictions[0]


    return predictions


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
    # REMOVE NAN / INF
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


    # ========================================================
    # CASE 1
    #
    # MODEL ALREADY RETURNS PROBABILITIES
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
            'Model output detected as probabilities.'
        )

        probabilities = values


    # ========================================================
    # CASE 2
    #
    # MODEL RETURNS LOGITS
    # ========================================================

    else:

        print(
            'Model output detected as logits.'
        )

        print(
            'Applying softmax...'
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
            ),

        'config_path':
            CONFIG_PATH,

        'config_exists':
            os.path.isfile(
                CONFIG_PATH
            )

    })


# ============================================================
# MODEL STATUS ENDPOINT
# ============================================================

@app.route(
    '/model-status',
    methods=['GET']
)
def model_status():

    try:

        model = get_model()

        return jsonify({

            'success':
                True,

            'model_loaded':
                True,

            'model_exists':
                os.path.isfile(
                    MODEL_PATH
                ),

            'model_path':
                MODEL_PATH,

            'input_shape':
                str(
                    model.input_shape
                ),

            'output_shape':
                str(
                    model.output_shape
                ),

            'classes':
                CLASSES

        })

    except Exception as e:

        return jsonify({

            'success':
                False,

            'model_loaded':
                False,

            'model_exists':
                os.path.isfile(
                    MODEL_PATH
                ),

            'model_path':
                MODEL_PATH,

            'error':
                str(e)

        }), 500


# ============================================================
# PREDICTION ENDPOINT
# ============================================================

@app.route(
    '/predict',
    methods=['POST']
)
def predict():

    # ========================================================
    # CHECK IMAGE FIELD
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
    # READ FILE
    # ========================================================

    file_bytes = file.read()


    # ========================================================
    # EMPTY IMAGE
    # ========================================================

    if not file_bytes:

        return jsonify({

            'success':
                False,

            'error':
                'Image file is empty.'

        }), 400


    # ========================================================
    # CHECK IMAGE SIZE
    # ========================================================

    if len(file_bytes) > MAX_IMAGE_BYTES:

        return jsonify({

            'success':
                False,

            'error':
                (
                    'Image too large. '
                    'Maximum allowed size is 5MB. '
                    f'Uploaded size: '
                    f'{len(file_bytes) // 1024} KB.'
                )

        }), 400


    try:

        print()
        print(
            "=============================================="
        )

        print(
            "NEW PADDY CLASSIFICATION REQUEST"
        )

        print(
            "=============================================="
        )

        print(
            'Filename:',
            file.filename
        )

        print(
            'Image size:',
            len(file_bytes),
            'bytes'
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
        # RUN MODEL
        # ====================================================

        print(
            'Running model inference...'
        )


        predictions = model(
            input_tensor,
            training=False
        )


        # ====================================================
        # EXTRACT MODEL OUTPUT
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
        # CHECK OUTPUT CLASS COUNT
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


        # ====================================================
        # VARIETY NAME
        # ====================================================

        if top_index < len(CLASSES):

            variety_name = CLASSES[
                top_index
            ]

        else:

            variety_name = 'Unknown'


        # ====================================================
        # ALL CLASS PREDICTIONS
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
        # SORT RESULTS
        # ====================================================

        sorted_predictions = sorted(
            predictions_map.items(),
            key=lambda x: x[1],
            reverse=True
        )


        # ====================================================
        # PRINT FINAL RESULT
        # ====================================================

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
        # API RESPONSE
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
    # MODEL NOT FOUND
    # ========================================================

    except FileNotFoundError as e:

        print()
        print(
            'MODEL FILE ERROR:'
        )

        print(
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
            'Error type:',
            type(e).__name__
        )

        print(
            'Error:',
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


    print()
    print(
        f'Starting Paddy Classification server '
        f'on port {port}'
    )

    print()


    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
