"""Generate periodic numerical PBR data for the PC source ceramic, not a scan.

RG: normal X/Y; B: roughness variation; A: low frequency glaze variation.
All channels are linear data. The 0.5 m repeat contains 6 micrometre RMS relief.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/textures/source_glaze'
SIZE = 512
REPEAT_METRES = 0.5
SEED = 20261023


def field(rng, wavelength, bandwidth):
    frequency = np.fft.fftfreq(SIZE, REPEAT_METRES / SIZE)
    x, y = np.meshgrid(frequency, frequency)
    radius = np.sqrt(x*x+y*y)
    spectrum = np.exp(-0.5*((radius-1/wavelength)/bandwidth)**2)
    spectrum[0, 0] = 0
    value = np.fft.ifft2(np.fft.fft2(rng.normal(size=(SIZE, SIZE)))*spectrum).real
    return value / value.std()


def generate():
    DEST.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    relief = field(rng, .018, 22)*.000006
    spacing = REPEAT_METRES / SIZE
    dx = (np.roll(relief, -1, axis=1)-np.roll(relief, 1, axis=1))/(2*spacing)
    dy = (np.roll(relief, -1, axis=0)-np.roll(relief, 1, axis=0))/(2*spacing)
    # Encode slopes at 4x for 8-bit precision; shader decodes the same scale.
    normal_xy = np.stack((-dx, -dy), axis=-1)*4
    roughness = np.clip(.5+field(rng, .035, 16)*.13, 0, 1)
    glaze = np.clip(.5+field(rng, .16, 6)*.12, 0, 1)
    packed = np.dstack((normal_xy*.5+.5, roughness, glaze))
    path = DEST/'glaze_detail.png'
    Image.fromarray(np.rint(np.clip(packed,0,1)*255).astype(np.uint8)).save(path)
    metadata = {
        'provenance':'Original deterministic numeric PBR data; no external source or photograph.',
        'generator':'tools/materials/build_source_glaze.py', 'seed':SEED,
        'size':[SIZE,SIZE], 'repeat_metres':REPEAT_METRES,
        'relief_rms_metres':float(relief.std()), 'slope_encoding_scale':4,
        'channels':'linear RG = encoded normal XY; B = roughness; A = glaze variation',
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    (DEST/'provenance.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf8')
    print(json.dumps(metadata))


if __name__ == '__main__':
    generate()
