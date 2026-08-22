import tensorflow as tf
import numpy as np
from PIL import Image

MODEL_PATH = r"E:\peddy\server\models\plant_disease\best_paddy_disease_model_fixed.keras"
IMAGE_PATH = r"D:\paddy-disease-classification\test_images\200049.jpg"

CLASSES = [
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

print("Loading model...")
model = tf.keras.models.load_model(MODEL_PATH)

print("Model loaded.")
print("Input shape:", model.input_shape)
print("Output shape:", model.output_shape)

print("\nLoading image...")
image = Image.open(IMAGE_PATH).convert("RGB")
print("Original image:", image.size)

image = image.resize((224, 224))

image_array = np.array(image, dtype=np.float32)
image_array = np.expand_dims(image_array, axis=0)

print("Running prediction...")

prediction = model.predict(image_array, verbose=1)

index = int(np.argmax(prediction[0]))
confidence = float(prediction[0][index])

print("\n==============================")
print("PREDICTION")
print("==============================")
print("Class:", CLASSES[index])
print("Confidence:", f"{confidence * 100:.2f}%")

print("\nAll probabilities:")
for class_name, probability in zip(CLASSES, prediction[0]):
    print(f"{class_name}: {probability * 100:.2f}%")