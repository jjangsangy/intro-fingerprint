# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def process_image_pdq(img_path_or_obj, target_width=64, target_height=64):
    """
    Processes an image using an approximation of the FFmpeg filter chain used in modules/video.lua.

    FFmpeg Chain:
    1. scale=512:512:flags=bilinear
    2. format=rgb24, colorchannelmixer (Rec.601 Grayscale)
    3. avgblur=sizeX=4:sizeY=4
    4. avgblur=sizeX=4:sizeY=4
    5. scale=64:64:flags=neighbor

    Approximation:
    1. Pillow Resize (512, 512, BILINEAR)
    2. Pillow Convert "L" (Rec.601)
    3. Pillow BoxBlur(1.5)
    4. Pillow BoxBlur(1.5)
    5. Pillow Resize (64, 64, NEAREST)
    """

    # Helper to process PIL Image
    def process_pil(img_pil):
        # 1. Resize 512x512 Bilinear
        # Note: FFmpeg scales to 512x512 first regardless of aspect ratio (ignoring AR).
        img_resized = img_pil.resize((512, 512), Image.Resampling.BILINEAR)

        # 2. Convert to Grayscale (Rec.601)
        # Pillow 'L' uses ITU-R 601-2: L = R * 299/1000 + G * 587/1000 + B * 114/1000
        img_gray = img_resized.convert("L")

        # 3 & 4. Two passes of Box Blur
        # FFmpeg avgblur size 4 is approx radius 1.5 in Pillow
        img_blur = img_gray.filter(ImageFilter.BoxBlur(1.5))
        img_blur = img_blur.filter(ImageFilter.BoxBlur(1.5))

        # 5. Decimate to target size (Nearest Neighbor)
        img_final = img_blur.resize(
            (target_width, target_height), Image.Resampling.NEAREST
        )

        return np.array(img_final, dtype=float)

    if isinstance(img_path_or_obj, (str, Path)):
        with Image.open(img_path_or_obj) as img:
            return process_pil(img)
    else:
        # Assume PIL Image object
        return process_pil(img_path_or_obj)


def generate_pdq_matrix() -> np.ndarray:
    """
    Generates the PDQ DCT matrix.
    Formula: D[u][x] = sqrt(2/64) * cos( (pi/64) * (x + 0.5) * u )
    Where u is frequency index (1..16) and x is spatial index (0..63).
    """
    print("Generating PDQ matrix...")

    # u: frequency 1..16 (Rows)
    u = np.arange(1, 17).reshape(-1, 1)
    # x: spatial 0..63 (Cols)
    x = np.arange(64).reshape(1, -1)

    matrix = np.sqrt(2 / 64) * np.cos((np.pi / 64) * (x + 0.5) * u)

    # Ensure shape is 16x64
    assert matrix.shape == (16, 64)

    return matrix


def process_image(input_path: Path, output_path: Path, dct_matrix: np.ndarray) -> None:
    print(f"Processing {input_path}...")

    # 1. Process image using correct Jarosz filter
    img_data = process_image_pdq(input_path)

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

    dct_matrix = generate_pdq_matrix()
    process_image(args.input, args.output, dct_matrix)


if __name__ == "__main__":
    main()
