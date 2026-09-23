// Replaced only in the explicitly requested local benchmark build.
declare const __POOL_BENCHMARK__: boolean;
export const BENCHMARK_BUILD=typeof __POOL_BENCHMARK__!=='undefined'&&__POOL_BENCHMARK__;
export const QA_ENABLED=process.env.NODE_ENV!=='production'||BENCHMARK_BUILD;
