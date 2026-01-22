# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy",
#     "pdqhash",
#     "pillow",
# ]
# ///

import argparse
import sys
from pathlib import Path

import numpy as np
import pdqhash
from PIL import Image


def bit_vector_to_hex(bit_vector):
    """
    Convert a numpy array of bits (0/1) to a hex string.
    Assumes the vector is 256 bits long.
    """
    val = 0
    for bit in bit_vector:
        val = (val << 1) | int(bit)
    return f"{val:064x}"


def main():
    parser = argparse.ArgumentParser(
        description="Generate PDQ hashes for images in a directory"
    )
    parser.add_argument(
        "images_dir", type=Path, help="Directory containing input images"
    )
    parser.add_argument(
        "output_file", type=Path, help="Path to output reference hashes file"
    )
    args = parser.parse_args()

    if not args.images_dir.exists():
        print(f"Error: {args.images_dir} not found")
        sys.exit(1)

    # Find images
    extensions = {".webp", ".png", ".jpg", ".jpeg"}
    image_files = sorted(
        [
            f
            for f in args.images_dir.iterdir()
            if f.is_file() and f.suffix.lower() in extensions
        ]
    )

    results = []

    print(f"Found {len(image_files)} images in {args.images_dir}")

    for img_path in image_files:
        try:
            print(f"Processing {img_path.name}...")
            with Image.open(img_path) as img:
                img = img.convert("RGB")
                img_arr = np.array(img)

            # Compute hash (returns vector, quality)
            vector, quality = pdqhash.compute(img_arr)

            computed_hash = bit_vector_to_hex(vector)

            results.append(f"{img_path.name}:{computed_hash}:{quality}")

        except Exception as e:
            print(f"[ERROR] processing {img_path.name}: {e}")
            sys.exit(1)

    # Write output
    try:
        with open(args.output_file, "w", encoding="utf-8") as f:
            for line in results:
                f.write(line + "\n")
        print(f"Successfully wrote {len(results)} hashes to {args.output_file}")
    except Exception as e:
        print(f"Error writing to output file: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
