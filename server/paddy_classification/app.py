
from pathlib import Path
import json

import spaces  # Import before torch for ZeroGPU
import gradio as gr
import timm
import torch
from PIL import Image

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "models" / "best_paddy_model.pt"
CLASS_PATH = BASE_DIR / "models" / "class_names.json"

ARCHITECTURE = "vit_base_patch16_224"

with open(CLASS_PATH, "r", encoding="utf-8") as f:
    CLASSES = json.load(f)

if len(CLASSES) != 8 or len(set(CLASSES)) != 8:
    raise ValueError("Expected exactly eight unique classes")

if not MODEL_PATH.is_file():
    raise FileNotFoundError(f"Model not found: {MODEL_PATH}")

# ------------------------------------------------------------
# Initialize model
# ------------------------------------------------------------

print(f"Loading model: {MODEL_PATH}")

model = timm.create_model(
    ARCHITECTURE,
    pretrained=False,
    num_classes=len(CLASSES),
)

checkpoint = torch.load(
    MODEL_PATH,
    map_location="cpu",
    weights_only=True,
)

if not isinstance(checkpoint, dict):
    raise TypeError("Expected a PyTorch state dictionary")

for key in ("state_dict", "model_state_dict", "model"):
    if key in checkpoint:
        checkpoint = checkpoint[key]
        break

if not isinstance(checkpoint, dict):
    raise TypeError("Invalid model weights")

# Support checkpoints saved using DataParallel.
if checkpoint and all(
    key.startswith("module.") for key in checkpoint
):
    checkpoint = {
        key.removeprefix("module."): value
        for key, value in checkpoint.items()
    }

model.load_state_dict(checkpoint, strict=True)
model.eval()

# Use the timm evaluation transform.
# Confirm it matches training preprocessing.
data_config = timm.data.resolve_model_data_config(model)
transform = timm.data.create_transform(
    **data_config,
    is_training=False,
)

# ZeroGPU stages model weights at application startup.
model = model.to("cuda")

print("ViT-Base model initialized successfully")
print("Classes:", CLASSES)

# ------------------------------------------------------------
# Inference
# ------------------------------------------------------------

@spaces.GPU
def predict(image: Image.Image):
    """Classify an RGB paddy image into eight varieties."""
    if image is None:
        raise gr.Error("Please upload an image")

    image = image.convert("RGB")
    tensor = transform(image).unsqueeze(0).to("cuda")

    with torch.inference_mode():
        logits = model(tensor)
        probabilities = torch.softmax(logits, dim=1)[0]
        probabilities = probabilities.float().cpu().tolist()

    predicted_index = max(
        range(len(probabilities)),
        key=lambda i: probabilities[i],
    )

    confidence = probabilities[predicted_index] * 100.0
    variety = CLASSES[predicted_index]

    label_scores = {
        name: float(probabilities[i])
        for i, name in enumerate(CLASSES)
    }

    response = {
        "success": True,
        "variety": variety,
        "confidence": round(confidence, 2),
        "class_index": predicted_index,
        "all_predictions": {
            name: round(probabilities[i] * 100.0, 2)
            for i, name in enumerate(CLASSES)
        },
    }

    return label_scores, json.dumps(response)

# ------------------------------------------------------------
# Gradio application
# ------------------------------------------------------------

demo = gr.Interface(
    fn=predict,
    inputs=gr.Image(
        type="pil",
        label="Upload Paddy Seed Image",
    ),
    outputs=[
        gr.Label(
            num_top_classes=8,
            label="Variety Predictions",
        ),
        gr.Textbox(
            label="Prediction JSON",
            lines=8,
        ),
    ],
    title="Paddy Seed Classification",
    description=(
        "Classify paddy seed images into eight varieties "
        "using a ViT-Base/16 model."
    ),
    flagging_mode="never",
    api_name="predict",
)

if __name__ == "__main__":
    demo.launch()
