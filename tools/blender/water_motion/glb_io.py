"""Minimal GLB container helper for append-only animation data; geometry untouched."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import struct
import numpy as np

DT={5120:np.dtype('i1'),5121:np.dtype('u1'),5122:np.dtype('<i2'),5123:np.dtype('<u2'),5125:np.dtype('<u4'),5126:np.dtype('<f4')}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
CLOTH={0:'shirt_plain',3:'trousers_twill'}
FROZEN_SHA='cf30e23b692db289228921f1c128a3c7cd79022c53f98c4962ea05d2caa25f17'

class GLB:
    def __init__(self,path):
        self.path=Path(path);self.raw=self.path.read_bytes()
        magic,version,length=struct.unpack_from('<III',self.raw)
        assert magic==0x46546c67 and version==2 and length==len(self.raw)
        pos=12;self.j=None;self.bin=b''
        while pos<len(self.raw):
            size,kind=struct.unpack_from('<II',self.raw,pos);data=self.raw[pos+8:pos+8+size];pos+=8+size
            if kind==0x4e4f534a:self.j=json.loads(data)
            elif kind==0x004e4942:self.bin=data
        assert self.j is not None
    def acc(self,index):
        a=self.j['accessors'][index];v=self.j['bufferViews'][a['bufferView']]
        dtype=DT[a['componentType']];cols=NC[a['type']];size=dtype.itemsize
        assert not a.get('sparse')
        return np.ndarray((a['count'],cols),dtype=dtype,buffer=self.bin,
            offset=v.get('byteOffset',0)+a.get('byteOffset',0),
            strides=(v.get('byteStride',size*cols),size)).copy()
    def append(self,array,kind,component_type=5126,template=None,with_bounds=False):
        array=np.asarray(array,dtype=DT[component_type]);array=array.reshape(-1,NC[kind])
        while len(self.bin)%4:self.bin+=b'\0'
        view=len(self.j['bufferViews']);self.j['bufferViews'].append(dict(buffer=0,byteOffset=len(self.bin),byteLength=array.nbytes))
        self.bin+=array.tobytes()
        a=copy.deepcopy(template) if template else {}
        for key in ['sparse','byteOffset','min','max']:a.pop(key,None)
        a.update(bufferView=view,componentType=component_type,count=len(array),type=kind)
        if with_bounds:a.update(min=array.min(0).tolist(),max=array.max(0).tolist())
        index=len(self.j['accessors']);self.j['accessors'].append(a)
        return index
    def save(self,path):
        while len(self.bin)%4:self.bin+=b'\0'
        self.j['buffers'][0]['byteLength']=len(self.bin)
        js=json.dumps(self.j,separators=(',',':')).encode()
        js+=b' '*((-len(js))%4)
        body=struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(self.bin),0x004e4942)+self.bin
        Path(path).write_bytes(struct.pack('<III',0x46546c67,2,len(body)+12)+body)
