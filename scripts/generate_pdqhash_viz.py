# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import argparse
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def load_pdq_matrix(modules_path: Path) -> np.ndarray:
    matrix_file = modules_path / "pdq_matrix.lua"
    if not matrix_file.exists():
        # Try finding it relative to current working directory if not found relative to script
        matrix_file = Path("modules") / "pdq_matrix.lua"
        if not matrix_file.exists():
            print(
                f"Error: Could not find pdq_matrix.lua in {modules_path} or ./modules"
            )
            sys.exit(1)

    print(f"Loading matrix from {matrix_file}...")
    with open(matrix_file, "r", encoding="utf-8") as f:
        content = f.read()

    # Find all floating point numbers
    # Matches: optional sign, digits, dot, digits, optional scientific notation
    # This should capture numbers like 0.123, -0.123, 1.23e-5
    floats = re.findall(r"[-+]?\d*\.\d+(?:[eE][-+]?\d+)?", content)

    if len(floats) != 1024:  # 16 * 64
        print(
            f"Error: Expected 1024 coefficients in pdq_matrix.lua, found {len(floats)}"
        )
        sys.exit(1)

    data = np.array([float(x) for x in floats], dtype=float)
    return data.reshape((16, 64))


def process_image(input_path: Path, output_path: Path, dct_matrix: np.ndarray) -> None:
    print(f"Processing {input_path}...")

    # 1. Load image
    with Image.open(input_path) as img:
        # Jarosz Filter Chain (matches modules/ffmpeg.lua)

        # 1. Scale to 512x512 (Bilinear)
        # ffmpeg: scale=512:512:flags=bilinear
        img = img.resize((512, 512), Image.Resampling.BILINEAR)

        # 2. RGB -> Luminance -> Grayscale
        # ffmpeg: format=rgb24, colorchannelmixer=..., format=gray
        # PIL .convert("L") uses Rec. 601 coefficients (0.299, 0.587, 0.114) matches ffmpeg mixer
        img = img.convert("L")

        # 3. Box Blur (Radius 2, Power 2)
        # ffmpeg: boxblur=2:2
        img = img.filter(ImageFilter.BoxBlur(2))
        img = img.filter(ImageFilter.BoxBlur(2))

        # 4. Scale to 64x64 (Area)
        # ffmpeg: scale=64:64:flags=area
        # Use reduce(8) for true area averaging (512 / 8 = 64)
        img = img.reduce(8)

    # Convert to numpy array (64x64)
    img_data = np.array(img, dtype=float)

    # 4. Compute PDQ DCT
    # Forward: Output = D @ Input @ D.T
    # D is 16x64
    # Input is 64x64
    # D @ Input -> 16x64
    # (D @ Input) @ D.T -> 16x64 @ 64x16 -> 16x16

    # Note: modules/video.lua computes:
    # Intermediate = D @ Input
    # Output = Intermediate @ D.T
    # So coeffs = D @ img_data @ D.T

    coeffs = dct_matrix @ img_data @ dct_matrix.T

    # 5. Reconstruct Image (Inverse transform)
    # We want to see what this 16x16 representation looks like in spatial domain.
    # Inverse: Reconstructed = D.T @ Coeffs @ D
    # D.T is 64x16
    # Coeffs is 16x16
    # D is 16x64
    # Result is 64x64

    reconstructed = dct_matrix.T @ coeffs @ dct_matrix

    # 6. Normalize for visualization
    # The PDQ matrix excludes the DC component (average brightness), so the
    # reconstructed signal is centered around 0 (representing gradients/edges).
    # To visualize this, we shift by 128 (mid-gray) and clip.
    # We also apply a slight contrast boost if needed, but standard +128 is usually best
    # for visualizing raw gradients.

    reconstructed = reconstructed + 128.0
    reconstructed = np.clip(reconstructed, 0, 255)

    img_result = Image.fromarray(reconstructed.astype(np.uint8))

    # 7. Upscale to 256x256 for better visibility
    img_result = img_result.resize((256, 256), Image.Resampling.NEAREST)

    # Save result
    img_result.save(output_path)
    print(f"Saved to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate PDQ Hash visualization.")
    parser.add_argument("input", type=Path, help="Input image path")
    parser.add_argument("output", type=Path, help="Output image path")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: {args.input} does not exist.")
        sys.exit(1)

    # Locate modules directory relative to this script
    script_dir = Path(__file__).resolve().parent
    # Assuming standard structure: root/scripts/script.py and root/modules/
    project_root = script_dir.parent
    modules_dir = project_root / "modules"

    dct_matrix = load_pdq_matrix(modules_dir)
    process_image(args.input, args.output, dct_matrix)


if __name__ == "__main__":
    main()
