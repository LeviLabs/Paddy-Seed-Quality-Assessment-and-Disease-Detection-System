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

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAVED_MODEL_PATH = os.path.join(BASE_DIR, 'models', 'saved_model')
JSON_PATH = os.path.join(BASE_DIR, 'models', 'class_names.json')

DEFAULT_CLASSES = [
    'Aumithri', 'Bpt', 'Hmt', 'Ir_64',
    'Mota_Mahamaya', 'Mota_Paan', 'Rb_Gold', 'Sarna'
]

def load_class_names():
    if os.path.isfile(JSON_PATH):
        try:
            with open(JSON_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
                elif isinstance(data, dict):
                    return [data[str(i)] for i in range(len(data))]
        except Exception as e:
            print(f'Warning loading class names: {e}')
    return DEFAULT_CLASSES

CLASSES = load_class_names()
print(f'Loaded {len(CLASSES)} paddy classes: {CLASSES}')

_model_infer_fn = None

def get_infer_fn():
    global _model_infer_fn
    if _model_infer_fn is None:
        print(f'Loading Paddy ConvNeXt-Tiny Model from {SAVED_MODEL_PATH}...')
        imported_model = tf.saved_model.load(SAVED_MODEL_PATH)
        _model_infer_fn = imported_model.signatures['serving_default']
        print('Paddy ConvNeXt-Tiny Model loaded successfully.')
    return _model_infer_fn

MAX_IMAGE_BYTES = 5 * 1024 * 1024

def preprocess_image_bytes(file_bytes, target_size=(320, 320)):
    image = Image.open(io.BytesIO(file_bytes))
    image = image.convert('RGB')
    image = image.resize(target_size, Image.Resampling.BILINEAR)
    img_array = np.asarray(image, dtype=np.float32)
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

@app.route('/', methods=['GET'])
def index():
    return jsonify({'success': True, 'service': 'Paddy ConvNeXt-Tiny Classification', 'endpoint': 'POST /predict'})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'success': True,
        'status': 'healthy',
        'service': 'paddy_classification',
        'architecture': 'ConvNeXt-Tiny',
        'classes': CLASSES,
        'total_classes': len(CLASSES),
        'model_exists': os.path.isdir(SAVED_MODEL_PATH)
    })

@app.route('/predict', methods=['POST'])
def predict():
    if 'image' not in request.files:
        return jsonify({'success': False, 'error': 'No image file provided.'}), 400
    file = request.files['image']
    if file.filename == '':
        return jsonify({'success': False, 'error': 'Empty filename.'}), 400
    file_bytes = file.read()
    if not file_bytes:
        return jsonify({'success': False, 'error': 'Image file is empty.'}), 400
    if len(file_bytes) > MAX_IMAGE_BYTES:
        return jsonify({'success': False, 'error': f'Image too large. Max 5MB. Got {len(file_bytes)//1024}KB.'}), 400
    try:
        infer_fn = get_infer_fn()
        input_data = preprocess_image_bytes(file_bytes, target_size=(320, 320))
        input_tensor = tf.convert_to_tensor(input_data, dtype=tf.float32)
        
        predictions_dict = infer_fn(input_tensor)
        out_key = list(predictions_dict.keys())[0]
        probabilities = predictions_dict[out_key].numpy()[0]
        probabilities = [float(p) for p in probabilities]

        top_index = int(np.argmax(probabilities))
        variety_name = CLASSES[top_index] if top_index < len(CLASSES) else 'Unknown'
        confidence = probabilities[top_index]

        predictions_map = {}
        for idx, prob in enumerate(probabilities):
            cls_name = CLASSES[idx] if idx < len(CLASSES) else f'class_{idx}'
            predictions_map[cls_name] = round(prob * 100, 2)

        if confidence >= 0.85:
            grade = 'Grade A (Premium Quality)'
            quality_score = 92
        elif confidence >= 0.70:
            grade = 'Grade B (Standard Commercial Quality)'
            quality_score = 80
        else:
            grade = 'Grade C (Mixed / Low Quality)'
            quality_score = 65

        return jsonify({
            'success': True,
            'variety': variety_name,
            'grade': grade,
            'quality_score': quality_score,
            'confidence': round(confidence * 100, 2),
            'moisture': 13.5,
            'class_index': top_index,
            'all_predictions': predictions_map
        })
    except UnidentifiedImageError:
        return jsonify({'success': False, 'error': 'Uploaded file is not a valid image.'}), 400
    except Exception as e:
        print(f'Prediction error: {e}')
        return jsonify({'success': False, 'error': f'Inference error: {str(e)}'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
