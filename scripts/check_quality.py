# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image


def calculate_entropy(data):
    """Calculate Shannon entropy of the image data."""
    # data is a 1D numpy array of pixel values (0-255)
    counts = np.bincount(data.astype(int), minlength=256)
    total = len(data)
    entropy = 0.0

    for count in counts:
        if count > 0:
            p = count / total
            entropy -= p * math.log2(p)

    return entropy


def calculate_gradient_sum_quality(img_array):
    """Calculate PDQ Gradient Sum Quality."""
    # img_array is 64x64 numpy array
    # Lua logic:
    # Gradient Sum = sum(|u - v|) for all adjacent pixels (Horiz and Vert)
    # Then divide by 255.0
    # Quality = Gradient Sum / 90.0

    h, w = img_array.shape
    gradient_sum = 0.0

    # Vertical diffs (y loops 0 to h-2)
    # u = pixel[y, x], v = pixel[y+1, x]
    diff_y = np.abs(img_array[:-1, :] - img_array[1:, :])
    gradient_sum += np.sum(diff_y)

    # Horizontal diffs (x loops 0 to w-2)
    # u = pixel[y, x], v = pixel[y, x+1]
    diff_x = np.abs(img_array[:, :-1] - img_array[:, 1:])
    gradient_sum += np.sum(diff_x)

    gradient_sum = gradient_sum / 255.0
    quality = gradient_sum / 90.0
    return quality


def check_quality(image_path: Path):
    print(f"Checking {image_path.name}...")

    try:
        with Image.open(image_path) as img:
            # 1. Convert to grayscale
            img_gray = img.convert("L")
            # 2. Resize to 64x64
            img_resized = img_gray.resize((64, 64), Image.Resampling.LANCZOS)

        img_array = np.array(img_resized, dtype=float)
        flat_data = img_array.flatten()

        # 1. Mean Brightness
        mean = np.mean(flat_data)

        # 2. Standard Deviation (Contrast)
        std_dev = np.std(flat_data)

        # 3. Entropy
        entropy = calculate_entropy(flat_data)

        # 4. Gradient Sum Quality
        quality = calculate_gradient_sum_quality(img_array)

        print(f"  Mean Brightness: {mean:.2f} (Threshold: 25 < x < 230)")
        print(f"  Contrast (StdDev): {std_dev:.2f} (Threshold: > 10.0)")
        print(f"  Entropy: {entropy:.2f} (Threshold: > 4.0)")
        print(f"  Gradient Quality: {quality:.4f} (Threshold: > 1.0)")

        failures = []
        if mean < 25:
            failures.append(f"Too Dark (Mean: {mean:.1f})")
        if mean > 230:
            failures.append(f"Too Bright (Mean: {mean:.1f})")
        if std_dev < 10.0:
            failures.append(f"Low Contrast (StdDev: {std_dev:.1f})")
        if entropy < 4.0:
            failures.append(f"Low Information (Entropy: {entropy:.1f})")
        if quality < 1.0:
            failures.append(f"Low Quality (Gradient: {quality:.3f})")

        if failures:
            print(f"  ❌ FAILED: {', '.join(failures)}")
        else:
            print("  ✅ PASSED")
        print("-" * 40)

    except Exception as e:
        print(f"  Error processing {image_path}: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Check image quality metrics for PDQ Hash."
    )
    parser.add_argument("images", nargs="+", type=Path, help="Input images to check")
    args = parser.parse_args()

    print("-" * 40)
    for img_path in args.images:
        if img_path.exists():
            check_quality(img_path)
        else:
            print(f"Error: {img_path} does not exist.")


if __name__ == "__main__":
    main()
