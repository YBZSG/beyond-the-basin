import { defineConfig } from 'vite';
import base from './vite.apk.config';
export default defineConfig({...base,define:{__POOL_BENCHMARK__:'true'},build:{...base.build,outDir:'../dist/benchmark'},server:{host:'127.0.0.1'},preview:{host:'127.0.0.1'}});
