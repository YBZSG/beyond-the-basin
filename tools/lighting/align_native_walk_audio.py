#!/usr/bin/env python3
"""Verify decoded walk pixels against native MovieWriter before trimming its WAV.
No frame-offset inference, image processing, synthesized audio, or source overwrite.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import wave
from PIL import Image

def pixels(path):
    with Image.open(path) as image:
        rgba = image.convert('RGBA')
        return (rgba.size, hashlib.sha256(rgba.tobytes()).hexdigest())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def align(manual_dir, movie_dir, wav_path, walk_report, out, report_path):
    if out.exists() or report_path.exists():
        raise ValueError('Refusing to overwrite audio or validation evidence')
    walk = json.loads(walk_report.read_text())
    if not walk.get('pass') or not walk.get('movie_writer_requested') or walk.get('frames') != 144 or walk.get('playback_fps') != 24:
        raise ValueError('A successful actual 144-frame 24 FPS MovieWriter walk is required')
    manual = [manual_dir / f'{index:04d}.png' for index in range(144)]
    expected = [pixels(path) for path in manual]
    if any(size != (1280, 720) for size, _ in expected):
        raise ValueError('Actual manual frames must all be 1280x720')
    movie = {}
    for path in movie_dir.glob('*.png'):
        match = re.search(r'(\d+)\.png$', path.name)
        if match:
            index = int(match.group(1))
            if index in movie: raise ValueError('Ambiguous duplicate MovieWriter frame index')
            movie[index] = path
    if not 144 <= len(movie) <= 10000: raise ValueError('Missing or unexpectedly unbounded movie sequence')
    hashes = {}
    def frame(index):
        if index not in hashes: hashes[index] = pixels(movie[index])
        return hashes[index]
    starts = []
    for index in sorted(movie):
        if index + 143 not in movie or frame(index) != expected[0]: continue
        if all(index + offset in movie and frame(index + offset) == expected[offset] for offset in range(144)):
            starts.append(index)
    if len(starts) != 1:
        raise ValueError(f'Expected one exact contiguous decoded-pixel match, got {len(starts)}')
    start = starts[0]
    with wave.open(str(wav_path), 'rb') as source:
        if source.getframerate() % 24: raise ValueError('Sample rate is not exactly divisible by 24 FPS')
        if source.getcomptype() != 'NONE': raise ValueError('Only native uncompressed PCM WAV is accepted')
        samples_per_frame = source.getframerate() // 24
        first_sample = start * samples_per_frame
        sample_count = 144 * samples_per_frame
        if source.getnframes() < first_sample + sample_count: raise ValueError('Native WAV is incomplete')
        # MovieWriter starts its first PNG/audio block at frame index zero.
        if min(movie) != 0: raise ValueError('Original MovieWriter frame zero is required for sample indexing')
        source.setpos(first_sample)
        audio = source.readframes(sample_count)
        parameters = source.getparams()
        stride = source.getnchannels() * source.getsampwidth()
        if len(audio) != sample_count * stride: raise ValueError('Short native audio data')
    with wave.open(str(out), 'wb') as target:
        target.setparams(parameters)
        target.writeframes(audio)
    with wave.open(str(out), 'rb') as target:
        if target.getnframes() != sample_count or target.readframes(sample_count) != audio:
            raise ValueError('Saved audio is not an exact PCM slice')
    result = {'pass':True,'frames':144,'fps':24,'movie_first_matched_frame':start,
        'first_audio_sample':first_sample,'audio_sample_count':sample_count,
        'sample_rate':parameters.framerate,'channels':parameters.nchannels,'sample_width_bytes':parameters.sampwidth,
        'audio_seconds':sample_count/parameters.framerate,'source_wav':str(wav_path),'source_wav_sha256':sha(wav_path),
        'aligned_wav':str(out),'aligned_wav_sha256':sha(out),'walk_report_sha256':sha(walk_report),
        'all_decoded_pixels_exact':True,'unique_walk_pixel_hashes':len({h for _,h in expected}),
        'frames_evidence':[{'manual':str(manual[i]),'movie':str(movie[start+i]),'decoded_rgba_sha256':expected[i][1]} for i in range(144)],
        'scope':'Actual manually saved walk frames exactly match a unique contiguous native MovieWriter sequence; WAV is a byte-exact PCM slice at that proven offset. Offline fixed-step capture is not realtime performance evidence.'}
    report_path.write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    for name in ['manual-dir','movie-dir','wav','walk-report','output-wav','report']: p.add_argument('--'+name,required=True,type=Path)
    a=p.parse_args()
    result=align(a.manual_dir,a.movie_dir,a.wav,a.walk_report,a.output_wav,a.report)
    print(json.dumps({k:result[k] for k in ['pass','frames','movie_first_matched_frame','audio_seconds','all_decoded_pixels_exact']}))
