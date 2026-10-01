import io
import os
import json

os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

import numpy as np
from PIL import Image, UnidentifiedImageError
from flask import Flask, jsonify, request
from flask_cors import CORS
import tensorflow as tf
from tensorflow.keras.applications.convnext import preprocess_input


app = Flask(__name__)
CORS(app)


# ============================================================
# BASE PATHS
# ============================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SAVED_MODEL_PATH = os.path.join(
    BASE_DIR,
    'models',
    'paddy_classification',
    'saved_model'
)

JSON_PATH = os.path.join(
    BASE_DIR,
    'models',
    'paddy_classification',
    'class_names.json'
)


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

                if isinstance(data, list):
                    return data

                elif isinstance(data, dict):
                    return [
                        data[str(i)]
                        for i in range(len(data))
                    ]

        except Exception as e:

            print(
                f'Warning loading class names: {e}'
            )

    return DEFAULT_CLASSES


CLASSES = load_class_names()

print(
    f'Loaded {len(CLASSES)} paddy classes: {CLASSES}'
)


# ============================================================
# MODEL
# ============================================================

_model_infer_fn = None


def get_infer_fn():

    global _model_infer_fn

    if _model_infer_fn is None:

        print(
            f'Loading Paddy ConvNeXt-Tiny Model from: '
            f'{SAVED_MODEL_PATH}'
        )

        if not os.path.isdir(SAVED_MODEL_PATH):

            raise FileNotFoundError(
                f'SavedModel directory not found: '
                f'{SAVED_MODEL_PATH}'
            )

        imported_model = tf.saved_model.load(
            SAVED_MODEL_PATH
        )

        print(
            'Available SavedModel signatures:',
            list(imported_model.signatures.keys())
        )

        if 'serving_default' not in imported_model.signatures:

            raise RuntimeError(
                'SavedModel does not contain '
                '"serving_default" signature.'
            )

        _model_infer_fn = (
            imported_model.signatures[
                'serving_default'
            ]
        )

        print(
            'Paddy ConvNeXt-Tiny Model loaded successfully.'
        )

    return _model_infer_fn


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
        'Original image size:',
        image.size
    )

    print(
        'Original image mode:',
        image.mode
    )

    image = image.convert('RGB')

    image = image.resize(
        target_size,
        Image.Resampling.BILINEAR
    )

    img_array = np.asarray(
        image,
        dtype=np.float32
    )

    print(
        'Before ConvNeXt preprocessing:',
        'min =',
        float(np.min(img_array)),
        'max =',
        float(np.max(img_array))
    )

    img_array = np.expand_dims(
        img_array,
        axis=0
    )

    # IMPORTANT:
    # model_config.json specifies:
    # "preprocessing": "ConvNeXt preprocess_input"
    img_array = preprocess_input(
        img_array
    )

    print(
        'After ConvNeXt preprocessing:',
        'min =',
        float(np.min(img_array)),
        'max =',
        float(np.max(img_array))
    )

    print(
        'Final input shape:',
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
        'Raw output sum:',
        output_sum
    )

    print(
        'Raw output min:',
        float(np.min(values))
    )

    print(
        'Raw output max:',
        float(np.max(values))
    )

    # --------------------------------------------------------
    # Case 1:
    # Model already returns probabilities.
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
            'Output detected as probabilities.'
        )

        probabilities = values

    # --------------------------------------------------------
    # Case 2:
    # Model returns logits.
    # Apply softmax.
    # --------------------------------------------------------

    else:

        print(
            'Output detected as logits. '
            'Applying softmax.'
        )

        probabilities = tf.nn.softmax(
            values
        ).numpy()

    return probabilities


# ============================================================
# ROOT
# ============================================================

@app.route(
    '/',
    methods=['GET']
)
def index():

    return jsonify({

        'success': True,

        'service':
            'Paddy ConvNeXt-Tiny Classification',

        'architecture':
            'ConvNeXt-Tiny',

        'input_size':
            '320x320',

        'classes':
            CLASSES,

        'endpoint':
            'POST /predict'

    })


# ============================================================
# HEALTH
# ============================================================

@app.route(
    '/health',
    methods=['GET']
)
def health():

    return jsonify({

        'success': True,

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
            SAVED_MODEL_PATH,

        'model_exists':
            os.path.isdir(
                SAVED_MODEL_PATH
            )

    })


# ============================================================
# PREDICTION
# ============================================================

@app.route(
    '/predict',
    methods=['POST']
)
def predict():

    # --------------------------------------------------------
    # Check image
    # --------------------------------------------------------

    if 'image' not in request.files:

        return jsonify({

            'success': False,

            'error':
                'No image file provided.'

        }), 400


    file = request.files['image']


    if file.filename == '':

        return jsonify({

            'success': False,

            'error':
                'Empty filename.'

        }), 400


    file_bytes = file.read()


    if not file_bytes:

        return jsonify({

            'success': False,

            'error':
                'Image file is empty.'

        }), 400


    # --------------------------------------------------------
    # Image size limit
    # --------------------------------------------------------

    if len(file_bytes) > MAX_IMAGE_BYTES:

        return jsonify({

            'success': False,

            'error':
                'Image too large. '
                'Max 5MB. '
                f'Got {len(file_bytes) // 1024}KB.'

        }), 400


    try:

        # ====================================================
        # LOAD MODEL
        # ====================================================

        infer_fn = get_infer_fn()


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

        predictions_dict = infer_fn(
            input_tensor
        )


        # ====================================================
        # DEBUG MODEL OUTPUT
        # ====================================================

        print(
            '========== MODEL OUTPUT DEBUG =========='
        )

        print(
            'Output keys:',
            list(predictions_dict.keys())
        )


        for key, value in predictions_dict.items():

            print(
                'Output key:',
                key
            )

            print(
                'Output shape:',
                value.shape
            )

            print(
                'Output dtype:',
                value.dtype
            )

            print(
                'Raw output:',
                value.numpy()[0]
            )


        print(
            '========================================'
        )


        # ====================================================
        # GET OUTPUT
        # ====================================================

        out_key = list(
            predictions_dict.keys()
        )[0]


        raw_output = predictions_dict[
            out_key
        ].numpy()[0]


        # ====================================================
        # CHECK OUTPUT SIZE
        # ====================================================

        if len(raw_output) != len(CLASSES):

            return jsonify({

                'success': False,

                'error':
                    'Model output class count does not '
                    'match class_names.json.',

                'model_output_classes':
                    len(raw_output),

                'class_names_count':
                    len(CLASSES)

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

            else 'Unknown'

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
                    f'class_{idx}'
                )


            predictions_map[cls_name] = round(
                float(prob) * 100,
                2
            )


        # ====================================================
        # SORTED PREDICTIONS FOR LOGGING
        # ====================================================

        sorted_predictions = sorted(
            predictions_map.items(),
            key=lambda x: x[1],
            reverse=True
        )


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
            'All predictions:',
            sorted_predictions
        )

        print(
            '======================================'
        )


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
    # GENERAL ERROR
    # ========================================================

    except Exception as e:

        print(
            f'Prediction error: {e}'
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

    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
