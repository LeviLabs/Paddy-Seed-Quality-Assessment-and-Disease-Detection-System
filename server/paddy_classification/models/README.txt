
PADDY SEED CLASSIFICATION MODEL
================================

Architecture:
ConvNeXt-Tiny

Input:
320 x 320 x 3

Output:
8 classes

Classes:
1. Aumithri
2. Bpt
3. Hmt
4. Ir_64
5. Mota_Mahamaya
6. Mota_Paan
7. Rb_Gold
8. Sarna

Total Parameters:
3248264

Files:
--------------------------------
paddy_convnext_tiny.keras
    Complete trained neural-network model (.keras format).
    Includes architecture, weights, and optimizer state.

paddy_convnext_tiny.weights.h5
    Trained neural-network weights.

class_names.json
    Class index to class-name mapping.

model_config.json
    Model configuration.

saved_model/
    TensorFlow SavedModel exported from
    the currently trained model.

HOW TO LOAD IN PYTHON / KERAS:
--------------------------------
import tensorflow as tf

model = tf.keras.models.load_model("paddy_convnext_tiny.keras")
