#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

#include <cuda_runtime.h>
#include "uniwers.h"
#include "blake2b.h"
#include <sys/time.h>

__constant__ uint64_t zero_blake[8];
__constant__ uint8_t sigma_matrix[192];

__constant__ uint64_t blake2b_IV_gpu[8] = {
        0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
        0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
        0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
        0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};


void load_constant_data(void) {
    static const uint8_t blake2b_sigma[192] = {
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
            11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
            7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
            9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
            2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
            12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
            13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
            6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
            10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3};

    TRY(cudaMemcpyToSymbol(zero_blake, &blake2b_IV, sizeof(blake2b_IV)));
    TRY(cudaMemcpyToSymbol(sigma_matrix, &blake2b_sigma, sizeof(blake2b_sigma)));
}

__device__ void load_constant_data_gpu(void) {
    static const uint8_t blake2b_sigma[192] = {
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
            11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
            7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
            9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
            2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
            12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
            13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
            6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
            10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3};


    memcpy(zero_blake, &blake2b_IV_gpu, sizeof(blake2b_IV_gpu));
    memcpy(sigma_matrix, &blake2b_sigma, sizeof(blake2b_sigma));

//    TRY(cudaMemcpyToSymbol(zero_blake, &blake2b_IV, sizeof(blake2b_IV)));
//    TRY(cudaMemcpyToSymbol(sigma_matrix, &blake2b_sigma, sizeof(blake2b_sigma)));
}

__device__ void store32_gpu(void *dst, uint32_t w) {
#if defined(NATIVE_LITTLE_ENDIAN)
    memcpy(dst, &w, sizeof w);
#else
    uint8_t *p = ( uint8_t * )dst;
    p[0] = (uint8_t)(w >>  0); p[1] = (uint8_t)(w >>  8); p[2] = (uint8_t)(w >> 16); p[3] = (uint8_t)(w >> 24);
#endif
}

__device__ uint64_t load64_gpu(const void *src) {
#if defined(NATIVE_LITTLE_ENDIAN)
    uint64_t w;
  memcpy(&w, src, sizeof w);
  return w;
#else
    const uint8_t *p = (const uint8_t *) src;
    return ((uint64_t)(p[0]) << 0) | ((uint64_t)(p[1]) << 8) | ((uint64_t)(p[2]) << 16) | ((uint64_t)(p[3]) << 24) |
           ((uint64_t)(p[4]) << 32) | ((uint64_t)(p[5]) << 40) | ((uint64_t)(p[6]) << 48) | ((uint64_t)(p[7]) << 56);
#endif
}

// Blake Inits
__device__ void blake2b_init0_gpu(blake2b_state *S) {
    size_t i;
    memset(S, 0, sizeof(blake2b_state));

    for (i = 0; i < 8; ++i) S->h[i] = blake2b_IV_gpu[i];
}

/* init xors IV with input parameter block */
__device__ int blake2b_init_param_gpu(blake2b_state *S, const blake2b_param *P) {
    const uint8_t *p = (const uint8_t *) (P);
    size_t i;

    blake2b_init0_gpu(S);

    /* IV XOR ParamBlock */
    for (i = 0; i < 8; ++i)
        S->h[i] ^= load64_gpu(p + sizeof(S->h[i]) * i);

    S->outlen = P->digest_length;
    return 0;
}

__device__ int blake2b_init_gpu(blake2b_state *S, size_t outlen) {
    blake2b_param P[1];

    if ((!outlen) || (outlen > BLAKE2B_OUTBYTES)) return -1;

    P->digest_length = (uint8_t) outlen;
    P->key_length = 0;
    P->fanout = 1;
    P->depth = 1;
    store32_gpu(&P->leaf_length, 0);
    store32_gpu(&P->node_offset, 0);
    store32_gpu(&P->xof_length, 0);
    P->node_depth = 0;
    P->inner_length = 0;
    memset(P->reserved, 0, sizeof(P->reserved));
    memset(P->salt, 0, sizeof(P->salt));
    memset(P->personal, 0, sizeof(P->personal));
    return blake2b_init_param_gpu(S, P);
}

__device__ blake2b_state ECh;
__device__ blake2b_state ECh0;

__inline__ __device__ void store64(void *dst, uint64_t word) {
    uint8_t *ltr = (uint8_t *) dst;
    ltr[0] = (uint8_t)(word >> 0);
    ltr[1] = (uint8_t)(word >> 8);
    ltr[2] = (uint8_t)(word >> 16);
    ltr[3] = (uint8_t)(word >> 24);
    ltr[4] = (uint8_t)(word >> 32);
    ltr[5] = (uint8_t)(word >> 40);
    ltr[6] = (uint8_t)(word >> 48);
    ltr[7] = (uint8_t)(word >> 56);
}

__inline__ __device__ uint64_t rshiftCircuit(uint64_t z1, uint64_t z2, short offset) {
    return ((z1 ^ z2) >> offset) | ((z1 ^ z2) << (64 - offset));
}

__inline__ __device__ void blakeRound(uint64_t *v_clmn[], uint64_t ext_1, uint64_t ext_2) {
    *v_clmn[0] = *v_clmn[0] + *v_clmn[1] + ext_1;
    *v_clmn[3] = rshiftCircuit(*v_clmn[3], *v_clmn[0], 32);
    *v_clmn[2] += *v_clmn[3];
    *v_clmn[1] = rshiftCircuit(*v_clmn[1], *v_clmn[2], 24);
    *v_clmn[0] = *v_clmn[0] + *v_clmn[1] + ext_2;
    *v_clmn[3] = rshiftCircuit(*v_clmn[3], *v_clmn[0], 16);
    *v_clmn[2] += *v_clmn[3];
    *v_clmn[1] = rshiftCircuit(*v_clmn[1], *v_clmn[2], 63);
}

__inline__ __device__ void matrixDiag(uint64_t matrix[4][4], short fixed_clmn) {
    matrix[1][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[1][fixed_clmn], fixed_clmn + 1, 4);
    matrix[2][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[2][fixed_clmn], fixed_clmn + 2, 4);
    matrix[3][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[3][fixed_clmn], fixed_clmn + 3, 4);
}

__inline__ __device__ void matrixUnDiag(uint64_t matrix[4][4], short fixed_clmn) {
    matrix[1][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[1][fixed_clmn], fixed_clmn - 1, 4);
    matrix[2][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[2][fixed_clmn], fixed_clmn - 2, 4);
    matrix[3][fixed_clmn] = __shfl_sync(0xFFFFFFFF, matrix[3][fixed_clmn], fixed_clmn - 3, 4);
}

__global__ void iter_compressor(const uint64_t *gmem_msg_block, size_t inlen, unsigned char *tgt, short stage_mark) {

    int idx = threadIdx.x;
    extern __shared__ uint64_t msg_block[];
    msg_block[idx] = gmem_msg_block[idx];
    msg_block[idx + 4] = gmem_msg_block[idx + 4];
    msg_block[idx + 8] = gmem_msg_block[idx + 8];
    msg_block[idx + 12] = gmem_msg_block[idx + 12];
    if (stage_mark == 0) {
        ECh.h[idx] = ECh0.h[idx];
        ECh.h[idx + 4] = ECh0.h[idx + 4];
        ECh.tf[idx] = ECh0.tf[idx];
    }

    if (idx == 0) {
        ECh.tf[0] += inlen;
        if (inlen < BLAKE2B_BLOCKBYTES) ECh.tf[2] = 0xffffffffffffffff;
    }
    __syncthreads();

    __shared__ uint64_t matrixState[4][4];
    matrixState[0][idx] = ECh.h[idx];
    matrixState[1][idx] = ECh.h[idx + 4];
    matrixState[2][idx] = zero_blake[idx];
    matrixState[3][idx] = zero_blake[idx + 4] ^ ECh.tf[idx];

    uint64_t *clmn[4] = {&matrixState[0][idx], &matrixState[1][idx], &matrixState[2][idx], &matrixState[3][idx]};
    for (short round = 0; round < 12; round++) {
        uint64_t ltr_1 = msg_block[sigma_matrix[16 * round + 2 * idx]];
        uint64_t ltr_2 = msg_block[sigma_matrix[16 * round + 2 * idx + 1]];
        blakeRound(clmn, ltr_1, ltr_2);

        // Diagonalyze
        matrixDiag(matrixState, idx);
        __syncthreads();

        ltr_1 = msg_block[sigma_matrix[16 * round + 2 * idx + 8]];
        ltr_2 = msg_block[sigma_matrix[16 * round + 2 * idx + 9]];
        blakeRound(clmn, ltr_1, ltr_2);

        // Return init-order
        matrixUnDiag(matrixState, idx);
        __syncthreads();
    }
    // Finalyze (all rounds) and keep results
    ECh.h[idx] = ECh.h[idx] ^ matrixState[0][idx] ^ matrixState[2][idx];
    ECh.h[idx + 4] = ECh.h[idx + 4] ^ matrixState[1][idx] ^ matrixState[3][idx];

    if (inlen < BLAKE2B_BLOCKBYTES) {
        store64(tgt + idx * sizeof(uint64_t), ECh.h[idx]);
        store64(tgt + (idx + 4) * sizeof(uint64_t), ECh.h[idx + 4]);
    }
}

__device__ void iter_compressor_gpu(const uint64_t *gmem_msg_block, size_t inlen, unsigned char *tgt, short stage_mark) {

    int idx = threadIdx.x;
    extern __shared__ uint64_t msg_block[];
    msg_block[idx] = gmem_msg_block[idx];
    msg_block[idx + 4] = gmem_msg_block[idx + 4];
    msg_block[idx + 8] = gmem_msg_block[idx + 8];
    msg_block[idx + 12] = gmem_msg_block[idx + 12];
    if (stage_mark == 0) {
        ECh.h[idx] = ECh0.h[idx];
        ECh.h[idx + 4] = ECh0.h[idx + 4];
        ECh.tf[idx] = ECh0.tf[idx];
    }

    if (idx == 0) {
        ECh.tf[0] += inlen;
        if (inlen < BLAKE2B_BLOCKBYTES) ECh.tf[2] = 0xffffffffffffffff;
    }
    __syncthreads();

    __shared__ uint64_t matrixState[4][4];
    matrixState[0][idx] = ECh.h[idx];
    matrixState[1][idx] = ECh.h[idx + 4];
    matrixState[2][idx] = zero_blake[idx];
    matrixState[3][idx] = zero_blake[idx + 4] ^ ECh.tf[idx];

    uint64_t *clmn[4] = {&matrixState[0][idx], &matrixState[1][idx], &matrixState[2][idx], &matrixState[3][idx]};
    for (short round = 0; round < 12; round++) {
        uint64_t ltr_1 = msg_block[sigma_matrix[16 * round + 2 * idx]];
        uint64_t ltr_2 = msg_block[sigma_matrix[16 * round + 2 * idx + 1]];
        blakeRound(clmn, ltr_1, ltr_2);

        // Diagonalyze
        matrixDiag(matrixState, idx);
        __syncthreads();

        ltr_1 = msg_block[sigma_matrix[16 * round + 2 * idx + 8]];
        ltr_2 = msg_block[sigma_matrix[16 * round + 2 * idx + 9]];
        blakeRound(clmn, ltr_1, ltr_2);

        // Return init-order
        matrixUnDiag(matrixState, idx);
        __syncthreads();
    }
    // Finalyze (all rounds) and keep results
    ECh.h[idx] = ECh.h[idx] ^ matrixState[0][idx] ^ matrixState[2][idx];
    ECh.h[idx + 4] = ECh.h[idx + 4] ^ matrixState[1][idx] ^ matrixState[3][idx];

    if (inlen < BLAKE2B_BLOCKBYTES) {
        store64(tgt + idx * sizeof(uint64_t), ECh.h[idx]);
        store64(tgt + (idx + 4) * sizeof(uint64_t), ECh.h[idx + 4]);
    }
}

__global__ void hash_gpu(const unsigned char *input, int len, unsigned char *hash) {
    printf("====:%s\n", input);
//    const char *vcm = "The quick brown fox jumps over the lazy dog";
    memcpy(hash, "abcde", 5);
//    const char *vcm = (const char *) input;
//    int src_len = len;
//    const unsigned char *src_word = (const unsigned char *) vcm;
//    short alt_hashlen = 64;
//    unsigned short outbytes = alt_hashlen;
//
////    TRY(cudaSetDevice(dev));
//    load_constant_data_gpu();
//
//    blake2b_state S[1];
//    blake2b_init_gpu(S, outbytes);
//
////    unsigned char *hash = (unsigned char *) malloc(outbytes * sizeof(char));
////    memset(hash, 0, outbytes * sizeof(char));
//
////    TRY(cudaMemcpyToSymbol(ECh0, S, sizeof(blake2b_state)));
//    memcpy((void *) &ECh0, S, sizeof(blake2b_state));
//
////    unsigned char *hash = (unsigned char *) malloc(outbytes * sizeof(char));
////    memset(hash, 0, outbytes * sizeof(char));
//    unsigned char *gpu_bfr_hash;
//    gpu_bfr_hash = (unsigned char *) malloc(BLAKE2B_OUTBYTES * sizeof(char));
//    memset(gpu_bfr_hash, 0, BLAKE2B_OUTBYTES * sizeof(char));
////    TRY(cudaMalloc((char **) &gpu_bfr_hash, BLAKE2B_OUTBYTES * sizeof(char)));
////    TRY(cudaMemset(gpu_bfr_hash, 0, BLAKE2B_OUTBYTES * sizeof(char)));
//
//    uint64_t *msg_h, *msg_r;
//    char *tail_block;
//
////    TRY(cudaMalloc((uint64_t * *) & msg_h, 16 * sizeof(uint64_t)));
////   TRY(cudaMalloc((char **) &tail_block, BLAKE2B_BLOCKBYTES));
//
//    msg_h = (uint64_t *) malloc(16 * sizeof(uint64_t));
//    tail_block = (char *) malloc(BLAKE2B_BLOCKBYTES);
//
//    int iter_num = 0;
//    while (src_len > BLAKE2B_BLOCKBYTES) {
//        for (int i = 0; i < 16; ++i) {
//            *(msg_h + i) = load64_gpu(src_word + iter_num * BLAKE2B_BLOCKBYTES + i * sizeof(uint64_t));
//        }
//
//        msg_r = (uint64_t *) malloc(16 * sizeof(uint64_t));
//        memcpy(msg_r, msg_h, 16 * sizeof(uint64_t));
////        TRY(cudaMalloc((uint64_t * *) & msg_r, 16 * sizeof(uint64_t)));
////        TRY(cudaMemcpy(msg_r, msg_h, 16 * sizeof(uint64_t), cudaMemcpyDeviceToDevice));
//        iter_compressor_gpu(msg_r, BLAKE2B_BLOCKBYTES, gpu_bfr_hash, iter_num);
////        TRY(cudaDeviceSynchronize());
//        free(msg_r);
////        TRY(cudaFree(msg_r));
//        src_len -= BLAKE2B_BLOCKBYTES;
//        ++iter_num;
//    }
//
//    memcpy(tail_block, src_word + iter_num * BLAKE2B_BLOCKBYTES, src_len);
//    memset(tail_block + src_len, 0, BLAKE2B_BLOCKBYTES - src_len);
//    for (int i = 0; i < 16; ++i) {
//        *(msg_h + i) = load64_gpu(tail_block + i * sizeof(uint64_t));
//    }
//
//    msg_r = (uint64_t *) malloc(16 * sizeof(uint64_t));
//    memcpy(msg_r, msg_h, 16 * sizeof(uint64_t));
//    iter_compressor_gpu(msg_r, src_len, gpu_bfr_hash, iter_num);
//
//    memcpy(hash, gpu_bfr_hash, outbytes * sizeof(char));
//
//    free(gpu_bfr_hash);

}

const unsigned char *cpu_call_hash_by_gpu(const unsigned char *input, int len) {
    short alt_hashlen = 64;
    unsigned short outbytes = alt_hashlen;
    printf("cpu_call_hash_by_gpu:%s\n", input);
    int dev = 0;
    TRY(cudaSetDevice(dev));

    unsigned char *gpu_bfr_hash;
    TRY(cudaMalloc((char **) &gpu_bfr_hash, BLAKE2B_OUTBYTES * sizeof(char)));
    TRY(cudaMemset(gpu_bfr_hash, 0, BLAKE2B_OUTBYTES * sizeof(char)));

    hash_gpu<<<1, 1, 16 * sizeof(uint64_t)>>>(input, len, gpu_bfr_hash);

    unsigned char *hash = (unsigned char *) malloc(outbytes * sizeof(char));
    memset(hash, 0, outbytes * sizeof(char));

    TRY(cudaMemcpy(hash, gpu_bfr_hash, outbytes * sizeof(char), cudaMemcpyDeviceToHost));

    printf(" Result: \n");
    for (int j = 0; j < outbytes; ++j) {
        printf("%02x", hash[j]);
    }
    printf("\n");
    return hash;
}

int get_usec() {
    struct timeval val;
    int ret = gettimeofday(&val, NULL);
    if (ret == -1) {
        printf("gettime err");
    }
    int timeLen1 = val.tv_sec * 100000 + val.tv_usec;
    return timeLen1;
}

const unsigned char *hash(const unsigned char *input, int len) {
//    printf("====:%s\n", input);
//    const char *vcm = "The quick brown fox jumps over the lazy dog";
    const char *vcm = (const char *) input;
    int src_len = len;
    const unsigned char *src_word = (const unsigned char *) vcm;
    short alt_hashlen = 64;
    unsigned short outbytes = alt_hashlen;

//    printf("com spent: 0000000000000000000000000000000000");
    int dev = 0;
    TRY(cudaSetDevice(dev));
    load_constant_data();

    blake2b_state S[1];
    blake2b_init(S, outbytes);
    TRY(cudaMemcpyToSymbol(ECh0, S, sizeof(blake2b_state)));
    unsigned char *hash = (unsigned char *) malloc(outbytes * sizeof(char));
    memset(hash, 0, outbytes * sizeof(char));
    unsigned char *gpu_bfr_hash;
    TRY(cudaMalloc((char **) &gpu_bfr_hash, BLAKE2B_OUTBYTES * sizeof(char)));
    TRY(cudaMemset(gpu_bfr_hash, 0, BLAKE2B_OUTBYTES * sizeof(char)));

    uint64_t *msg_h, *msg_r;
    char *tail_block;
    msg_h = (uint64_t *) malloc(16 * sizeof(uint64_t));
    tail_block = (char *) malloc(BLAKE2B_BLOCKBYTES);

    int diff = 0;
    int iter_num = 0;
    while (src_len > BLAKE2B_BLOCKBYTES) {
        for (int i = 0; i < 16; ++i) {
            *(msg_h + i) = load64(src_word + iter_num * BLAKE2B_BLOCKBYTES + i * sizeof(uint64_t));
        }
        TRY(cudaMalloc((uint64_t * *) & msg_r, 16 * sizeof(uint64_t)));
        TRY(cudaMemcpy(msg_r, msg_h, 16 * sizeof(uint64_t), cudaMemcpyHostToDevice));

        int timeLen1 = get_usec();
        iter_compressor<<<1, 4, 16 * sizeof(uint64_t)>>>(msg_r, BLAKE2B_BLOCKBYTES, gpu_bfr_hash, iter_num);

        int timeLen2 = get_usec();
//        printf("com spent:%d\n", timeLen2 - timeLen1);
        diff += timeLen2 - timeLen1;
        TRY(cudaDeviceSynchronize());
        TRY(cudaFree(msg_r));
        src_len -= BLAKE2B_BLOCKBYTES;
        ++iter_num;
    }
    memcpy(tail_block, src_word + iter_num * BLAKE2B_BLOCKBYTES, src_len);
    memset(tail_block + src_len, 0, BLAKE2B_BLOCKBYTES - src_len);
    for (int i = 0; i < 16; ++i) {
        *(msg_h + i) = load64(tail_block + i * sizeof(uint64_t));
    }
    TRY(cudaMalloc((uint64_t * *) & msg_r, 16 * sizeof(uint64_t)));
    TRY(cudaMemcpy(msg_r, msg_h, 16 * sizeof(uint64_t), cudaMemcpyHostToDevice));

    int timeLen1 = get_usec();
    iter_compressor<<<1, 4, 16 * sizeof(uint64_t)>>>(msg_r, src_len, gpu_bfr_hash, iter_num);
    int timeLen2 = get_usec();
    diff += timeLen2 - timeLen1;
    printf("end com spent:%d\n", diff);

    TRY(cudaMemcpy(hash, gpu_bfr_hash, outbytes * sizeof(char), cudaMemcpyDeviceToHost));

    TRY(cudaFree(gpu_bfr_hash));
//    free(hash);

    return (const unsigned char *) hash;
}

int main(int argc, char **argv) {
    //
//    unsigned char vcm[1] = {"The quick brown fox jumps over the lazy dog"};
    unsigned char vcm[1] = {""};

    int src_len = (argc < 2) ? 0 : strlen(argv[1]);
    const unsigned char *src_word = (argc < 2) ? vcm : (unsigned char *) argv[1];
    short alt_hashlen = (argc >= 3) ? atoi(argv[2]) : -1;
//    unsigned short outbytes = (alt_hashlen >= 10 && alt_hashlen < BLAKE2B_OUTBYTES) ? alt_hashlen : BLAKE2B_OUTBYTES;

    const unsigned char *hash = cpu_call_hash_by_gpu(src_word, src_len);

    free((void*)hash);
}
//
//int main(int argc, char **argv) {
//
//  unsigned char vcm[1] = {""};
//  int src_len = (argc < 2) ? 0 : strlen(argv[1]);
//  const unsigned char* src_word = (argc < 2) ? vcm : (unsigned char *)argv[1];
//  short alt_hashlen = (argc >= 3) ? atoi(argv[2]) : -1;
//  unsigned short outbytes = (alt_hashlen >= 10 && alt_hashlen < BLAKE2B_OUTBYTES) ? alt_hashlen : BLAKE2B_OUTBYTES;
//
//  printf("====:%s\n", argv[1]);
//  int dev = 0;
//  TRY(cudaSetDevice(dev));
//  load_constant_data ();
//
//  blake2b_state S[1];
//  blake2b_init(S, outbytes);
//  TRY(cudaMemcpyToSymbol(ECh0, S, sizeof(blake2b_state)));
//  unsigned char *hash = (unsigned char*) malloc(outbytes*sizeof(char)); memset(hash, 0, outbytes*sizeof(char));
//  unsigned char *gpu_bfr_hash; TRY(cudaMalloc((char**)&gpu_bfr_hash, BLAKE2B_OUTBYTES*sizeof(char))); TRY(cudaMemset(gpu_bfr_hash, 0, BLAKE2B_OUTBYTES*sizeof(char)));
//
//  uint64_t *msg_h, *msg_r; char *tail_block;
//  msg_h = (uint64_t *)malloc(16*sizeof(uint64_t));
//  tail_block = (char *)malloc(BLAKE2B_BLOCKBYTES);
//
//  int iter_num = 0;
//  while (src_len > BLAKE2B_BLOCKBYTES) {
//    for (int i = 0; i < 16; ++i) {
//        *(msg_h + i) = load64(src_word + iter_num*BLAKE2B_BLOCKBYTES + i*sizeof(uint64_t));
//    }
//    TRY(cudaMalloc((uint64_t**)&msg_r, 16*sizeof(uint64_t)));
//    TRY(cudaMemcpy(msg_r, msg_h, 16*sizeof(uint64_t), cudaMemcpyHostToDevice));
//    iter_compressor<<<1, 4, 16*sizeof(uint64_t)>>>(msg_r, BLAKE2B_BLOCKBYTES, gpu_bfr_hash, iter_num);
//    TRY(cudaDeviceSynchronize());
//    TRY(cudaFree(msg_r));
//    src_len -= BLAKE2B_BLOCKBYTES; ++iter_num;
//  }
//  memcpy(tail_block, src_word + iter_num*BLAKE2B_BLOCKBYTES, src_len);
//  memset(tail_block + src_len, 0, BLAKE2B_BLOCKBYTES - src_len);
//  for (int i = 0; i < 16; ++i) {
//      *(msg_h + i) = load64(tail_block + i*sizeof(uint64_t));
//  }
//  TRY(cudaMalloc((uint64_t**)&msg_r, 16*sizeof(uint64_t)));
//  TRY(cudaMemcpy(msg_r, msg_h, 16*sizeof(uint64_t), cudaMemcpyHostToDevice));
//  iter_compressor<<<1, 4, 16*sizeof(uint64_t)>>>(msg_r, src_len, gpu_bfr_hash, iter_num);
//
//  TRY(cudaMemcpy(hash, gpu_bfr_hash, outbytes*sizeof(char), cudaMemcpyDeviceToHost));
//
//  printf(" Result: \n");
//  for(int j = 0; j < outbytes; ++j){
//    printf( "%02x", hash[j] );}
//  printf("\n");
//
//  TRY(cudaFree(gpu_bfr_hash));
//  free(hash);
//
//  return 0;
//}
