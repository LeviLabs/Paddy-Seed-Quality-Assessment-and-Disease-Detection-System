import gradio as gr
import spaces
import torch
import timm
import json
import numpy as np
from PIL import Image

# ============================================================
# CLASS NAMES
# ============================================================

CLASSES = [
    "Aumithri",
    "Bpt",
    "Hmt",
    "Ir_64",
    "Mota_Mahamaya",
    "Mota_Paan",
    "Rb_Gold",
    "Sarna",
]

# ============================================================
# LOAD MODEL (CPU - ZeroGPU moves to GPU during inference)
# ============================================================

print("Creating ViT-Base model architecture...")
model = timm.create_model("vit_base_patch16_224", pretrained=False, num_classes=8)

print("Loading trained weights...")
checkpoint = torch.load("best_paddy_model.pt", map_location="cpu")

# Handle different checkpoint formats
if isinstance(checkpoint, dict):
    if "state_dict" in checkpoint:
        model.load_state_dict(checkpoint["state_dict"])
    elif "model" in checkpoint:
        model.load_state_dict(checkpoint["model"])
    elif "model_state_dict" in checkpoint:
        model.load_state_dict(checkpoint["model_state_dict"])
    else:
        model.load_state_dict(checkpoint)
else:
    model.load_state_dict(checkpoint)

model.eval()
print(f"Model loaded successfully! Classes: {CLASSES}")

# Get the correct image transform for this model
data_config = timm.data.resolve_model_data_config(model)
transform = timm.data.create_transform(**data_config, is_training=False)

# ============================================================
# INFERENCE (runs on GPU via ZeroGPU)
# ============================================================

@spaces.GPU
def predict(image):
    """Classify a paddy seed image into one of 8 varieties."""
    if image is None:
        return "No image provided", "{}"

    # image is already a PIL Image from Gradio
    tensor = transform(image).unsqueeze(0).cuda()
    model.cuda()

    with torch.no_grad():
        logits = model(tensor)
        probs = torch.nn.functional.softmax(logits[0], dim=0).cpu()

    top_idx = int(torch.argmax(probs))
    confidence = float(probs[top_idx])
    variety = CLASSES[top_idx]

    # Build results dict for Label output
    results = {CLASSES[i]: float(probs[i]) for i in range(len(CLASSES))}

    # Also build JSON response (for Flutter app via API)
    json_response = json.dumps({
        "success": True,
        "variety": variety,
        "confidence": round(confidence * 100, 2),
        "class_index": top_idx,
        "all_predictions": {
            CLASSES[i]: round(float(probs[i]) * 100, 2)
            for i in range(len(CLASSES))
        },
    })

    return results, json_response


# ============================================================
# GRADIO UI
# ============================================================

demo = gr.Interface(
    fn=predict,
    inputs=gr.Image(type="pil", label="Upload Paddy Seed Image"),
    outputs=[
        gr.Label(num_top_classes=8, label="Predictions"),
        gr.Textbox(label="API Response (JSON)", lines=8),
    ],
    title="🌾 Paddy Seed Classification",
    description=(
        "Upload an image of paddy seeds to classify them into one of "
        "8 varieties: Aumithri, Bpt, Hmt, Ir_64, Mota_Mahamaya, "
        "Mota_Paan, Rb_Gold, Sarna.\n\n"
        "**Model:** Vision Transformer (ViT-Base/16) trained on paddy seed dataset."
    ),
    examples=None,
    allow_flagging="never",
)

demo.launch()
