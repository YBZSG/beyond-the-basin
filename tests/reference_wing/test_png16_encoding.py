"""Lossless filter tests; no source assets are rewritten."""
from pathlib import Path
import sys
import tempfile
import unittest
import subprocess
import shutil
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/materials/reference_wing'))
from generate import png16
from test_materials import read_png16


class PNG16Encoding(unittest.TestCase):
    def check_array(self,values):
        with tempfile.TemporaryDirectory(prefix='png16-lossless-') as directory:
            path=Path(directory)/'a.png';other=Path(directory)/'b.png'
            stats=png16(path,values);png16(other,values)
            self.assertEqual(path.read_bytes(),other.read_bytes())
            np.testing.assert_array_equal(read_png16(path),values)
            self.assertEqual(stats['bytes_per_pixel'],6 if values.ndim==3 else 2)
            self.assertTrue(stats['row_filters'][1]+stats['row_filters'][2]+stats['row_filters'][4]>0)
            if shutil.which('ffmpeg'):
                fmt='rgb48be' if values.ndim==3 else 'gray16be'
                decoded=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(path),'-f','rawvideo','-pix_fmt',fmt,'-threads','1','-'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True).stdout
                np.testing.assert_array_equal(np.frombuffer(decoded,dtype='>u2').reshape(values.shape),values)

    def test_rgb16_byte_stride_extremes(self):
        a=np.array([0,1,255,256,257,32767,32768,65534,65535],dtype=np.uint16)
        values=np.resize(a,(64,97,3));values[1::2]=values[1::2,::-1]
        self.check_array(values)

    def test_gray16_byte_stride_and_predictors(self):
        y,x=np.mgrid[:128,:63]
        self.check_array(((x*x*37+y*719+x*y*9)%65536).astype(np.uint16))


if __name__=='__main__':unittest.main(verbosity=2)
