# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy",
#     "pillow",
#     "scipy",
# ]
# ///

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.fftpack import dct, idct


def process_image(input_path: Path, output_path: Path) -> None:
    print(f"Processing {input_path}...")

    # 1. Load image
    with Image.open(input_path) as img:
        # 2. Convert to grayscale
        img_gray = img.convert("L")
        # 3. Resize to 32x32
        img_resized = img_gray.resize((32, 32), Image.Resampling.LANCZOS)

    # Convert to numpy array
    data = np.array(img_resized, dtype=float)

    # 4. Compute DCT (Type II, ortho)
    # Perform 2D DCT
    dct_data = dct(dct(data.T, norm="ortho").T, norm="ortho")

    # 5. Extract 8x8 matrix (keep low frequencies)
    # Zero out everything else
    mask = np.zeros_like(dct_data)
    mask[:8, :8] = 1
    dct_filtered = dct_data * mask

    # 6. Compute IDCT (Type II, ortho) - effectively Type III inverse of Type II
    idct_data = idct(idct(dct_filtered.T, norm="ortho").T, norm="ortho")

    # 7. Normalize/Clip
    idct_data = np.clip(idct_data, 0, 255)
    img_result = Image.fromarray(idct_data.astype(np.uint8))

    # 8. Upscale to 256x256 for better visibility
    img_result = img_result.resize((256, 256), Image.Resampling.NEAREST)

    # Save result
    img_result.save(output_path)
    print(f"Saved to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate pHash visualization.")
    parser.add_argument("input", type=Path, help="Input image path")
    parser.add_argument("output", type=Path, help="Output image path")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: {args.input} does not exist.")
        sys.exit(1)

    process_image(args.input, args.output)


if __name__ == "__main__":
    main()
