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

import keras
from keras.models import load_model
from keras.layers import Dense
from keras.applications.efficientnet import preprocess_input

app = Flask(__name__)
CORS(app)

class CompatibleDense(Dense):
    @classmethod
    def from_config(cls, config):
        config = dict(config)
        config.pop('quantization_config', None)
        return super().from_config(config)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, 'models', 'paddy_disease.keras')
JSON_PATH = os.path.join(BASE_DIR, 'models', 'class_names.json')

DEFAULT_CLASSES = [
    'bacterial_leaf_blight', 'bacterial_leaf_streak',
    'bacterial_panicle_blight', 'blast', 'brown_spot',
    'dead_heart', 'downy_mildew', 'hispa', 'normal', 'tungro',
]

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
print(f'Loaded {len(CLASSES)} disease classes.')

_model = None

def get_model():
    global _model
    if _model is None:
        print(f'Loading Plant Disease Model...')
        _model = load_model(
            MODEL_PATH,
            compile=False,
            custom_objects={
                'Dense': CompatibleDense,
                'preprocess_input': preprocess_input,
            },
        )
        print('Plant Disease Model loaded.')
    return _model

MAX_IMAGE_BYTES = 5 * 1024 * 1024

def preprocess_image_bytes(file_bytes, target_size=(224, 224)):
    image = Image.open(io.BytesIO(file_bytes))
    image = image.convert('RGB')
    image = image.resize(target_size, Image.Resampling.BILINEAR)
    img_array = np.asarray(image, dtype=np.float32)
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

DISEASE_INFO = {
    'bacterial_leaf_blight': {'description': 'Bacterial leaf blight causes water-soaked to yellowish stripes on leaf blades.', 'treatment': 'Apply copper hydroxide or streptocycline spray. Ensure balanced potassium fertilization.'},
    'bacterial_leaf_streak': {'description': 'Narrow brownish-yellow interveinal streaks with amber bacterial exudates.', 'treatment': 'Ensure proper drainage and balanced nitrogen. Apply copper fungicides early.'},
    'bacterial_panicle_blight': {'description': 'Discoloration of panicles and florets, resulting in sterile or partially filled grains.', 'treatment': 'Use disease-free certified seeds. Avoid excess nitrogen during heading stage.'},
    'blast': {'description': 'Diamond-shaped lesions with gray centers and brown margins on leaves and panicle neck.', 'treatment': 'Apply Tricyclazole or Azoxystrobin. Maintain continuous shallow flooding.'},
    'brown_spot': {'description': 'Small round to oval brown spots with yellowish halos on leaves and glumes.', 'treatment': 'Apply Mancozeb or Propiconazole. Add potash and micronutrients.'},
    'dead_heart': {'description': 'Drying and death of the central tiller shoot from stem borer larval feeding.', 'treatment': 'Apply Cartap hydrochloride granules. Install pheromone traps.'},
    'downy_mildew': {'description': 'Stunted growth and yellow-white speckles on leaves with distorted panicles.', 'treatment': 'Improve field drainage. Treat seeds with Metalaxyl before planting.'},
    'hispa': {'description': 'White parallel streaks from the hispa beetle scraping leaf surfaces.', 'treatment': 'Clip affected leaf tips before transplanting. Spray Chlorpyrifos if infestation is high.'},
    'normal': {'description': 'Leaf appears healthy with no visible signs of disease or pest damage.', 'treatment': 'Maintain balanced N-P-K fertilization and monitor weekly.'},
    'tungro': {'description': 'Viral disease causing severe stunting and yellow-orange leaf discoloration.', 'treatment': 'Control green leafhopper with Imidacloprid. Use resistant varieties.'},
}

@app.route('/', methods=['GET'])
def index():
    return jsonify({'success': True, 'service': 'Plant Disease Detection', 'endpoint': 'POST /predict'})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'success': True, 'status': 'healthy', 'service': 'plant_disease', 'classes': CLASSES, 'total_classes': len(CLASSES), 'model_exists': os.path.isfile(MODEL_PATH)})

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
        raw_predictions = model.predict(input_data, batch_size=1, verbose=0)[0]
        probabilities = [float(p) for p in raw_predictions]
        top_index = int(np.argmax(probabilities))
        disease_name = CLASSES[top_index] if top_index < len(CLASSES) else 'unknown'
        confidence = probabilities[top_index]
        predictions_map = {CLASSES[i] if i < len(CLASSES) else f'class_{i}': round(p * 100, 2) for i, p in enumerate(probabilities)}
        info = DISEASE_INFO.get(disease_name, {'description': 'Diagnosis complete.', 'treatment': 'Follow standard crop protection guidelines.'})
        return jsonify({'success': True, 'disease': disease_name, 'confidence': round(confidence * 100, 2), 'class_index': top_index, 'description': info['description'], 'treatment': info['treatment'], 'predictions': predictions_map})
    except UnidentifiedImageError:
        return jsonify({'success': False, 'error': 'Uploaded file is not a valid image.'}), 400
    except Exception as e:
        print(f'Prediction error: {e}')
        return jsonify({'success': False, 'error': f'Inference error: {str(e)}'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
