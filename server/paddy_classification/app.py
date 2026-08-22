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

from keras.models import load_model

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, 'models', 'paddy_cnn.keras')
JSON_PATH = os.path.join(BASE_DIR, 'models', 'class_names.json')

DEFAULT_CLASSES = ['RB gold', 'mota pan dhan']

def load_class_names():
    if os.path.isfile(JSON_PATH):
        try:
            with open(JSON_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
                return [data[str(i)] for i in range(len(data))]
        except Exception as e:
            print(f'Warning loading class names: {e}')
    return DEFAULT_CLASSES

CLASSES = load_class_names()
print(f'Loaded {len(CLASSES)} paddy classes.')

_model = None

def get_model():
    global _model
    if _model is None:
        print(f'Loading Paddy Classification Model...')
        _model = load_model(MODEL_PATH, compile=False)
        print('Paddy Classification Model loaded.')
    return _model

MAX_IMAGE_BYTES = 5 * 1024 * 1024

def preprocess_image_bytes(file_bytes, target_size=(224, 224)):
    image = Image.open(io.BytesIO(file_bytes))
    image = image.convert('RGB')
    image = image.resize(target_size, Image.Resampling.BILINEAR)
    img_array = np.asarray(image, dtype=np.float32)
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

@app.route('/', methods=['GET'])
def index():
    return jsonify({'success': True, 'service': 'Paddy Classification', 'endpoint': 'POST /predict'})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'success': True, 'status': 'healthy', 'service': 'paddy_classification', 'classes': CLASSES, 'total_classes': len(CLASSES), 'model_exists': os.path.isfile(MODEL_PATH)})

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
        model = get_model()
        input_data = preprocess_image_bytes(file_bytes)
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
        variety_name = CLASSES[top_index] if top_index < len(CLASSES) else 'Unknown'
        if confidence >= 0.85:
            grade = 'Grade A (Premium Quality)'
            quality_score = 92
        elif confidence >= 0.70:
            grade = 'Grade B (Standard Commercial Quality)'
            quality_score = 80
        else:
            grade = 'Grade C (Mixed / Low Quality)'
            quality_score = 65
        return jsonify({'success': True, 'variety': variety_name, 'grade': grade, 'quality_score': quality_score, 'confidence': round(confidence * 100, 2), 'moisture': 13.5, 'class_index': top_index})
    except UnidentifiedImageError:
        return jsonify({'success': False, 'error': 'Uploaded file is not a valid image.'}), 400
    except Exception as e:
        print(f'Prediction error: {e}')
        return jsonify({'success': False, 'error': f'Inference error: {str(e)}'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
