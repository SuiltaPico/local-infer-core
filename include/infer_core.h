#ifndef INFER_CORE_H
#define INFER_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define INFER_CORE_API __declspec(dllexport)
#else
#define INFER_CORE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct InferRegistry InferRegistry;
typedef struct InferOcrEngine InferOcrEngine;
typedef struct InferEmbedEngine InferEmbedEngine;
typedef struct InferIconIndex InferIconIndex;

/* Returns a static version string (do not free). */
INFER_CORE_API const char *infer_core_version(void);

/* Free a string previously returned by this library. */
INFER_CORE_API void infer_string_free(char *s);

/* Free a float buffer previously returned by this library. */
INFER_CORE_API void infer_floats_free(float *data, size_t len);

/*
 * Open a manifest-driven registry under models_dir.
 * runtime_config_json may be null or empty for defaults.
 * On failure returns NULL and sets *out_error.
 */
INFER_CORE_API InferRegistry *infer_registry_create(
    const char *models_dir,
    const char *runtime_config_json,
    char **out_error);

INFER_CORE_API void infer_registry_destroy(InferRegistry *handle);

/* Returns JSON array of pack ids, e.g. ["ocr....","embed...."]. */
INFER_CORE_API int32_t infer_registry_pack_ids_json(
    InferRegistry *handle,
    char **out_json,
    char **out_error);

/* Returns manifest.json content for pack_id as JSON string. */
INFER_CORE_API int32_t infer_registry_manifest_json(
    InferRegistry *handle,
    const char *pack_id,
    char **out_json,
    char **out_error);

INFER_CORE_API InferOcrEngine *infer_ocr_engine_load(
    InferRegistry *registry,
    const char *pack_id,
    char **out_error);

INFER_CORE_API void infer_ocr_engine_destroy(InferOcrEngine *engine);

INFER_CORE_API int32_t infer_ocr_engine_apply_config(
    InferOcrEngine *engine,
    float min_confidence,
    uint32_t max_side,
    char **out_error);

/*
 * Recognize text in a PNG/JPEG/WebP buffer.
 * On success writes JSON to *out_json and returns 0.
 * JSON shape: {"words":[...],"timings":{"init_ms":0,"predict_ms":0}}
 */
INFER_CORE_API int32_t infer_ocr_recognize_timed(
    InferOcrEngine *engine,
    const uint8_t *data,
    size_t len,
    char **out_json,
    char **out_error);

/*
 * Recognize text from a width×height RGB888 buffer (3 bytes per pixel).
 * On success writes JSON to *out_json and returns 0.
 */
INFER_CORE_API int32_t infer_ocr_recognize_rgb_timed(
    InferOcrEngine *engine,
    const uint8_t *rgb,
    size_t len,
    uint32_t width,
    uint32_t height,
    char **out_json,
    char **out_error);

INFER_CORE_API InferEmbedEngine *infer_embed_engine_load(
    InferRegistry *registry,
    const char *pack_id,
    char **out_error);

INFER_CORE_API InferEmbedEngine *infer_embed_engine_load_path(
    const char *model_path,
    const char *runtime_config_json,
    char **out_error);

INFER_CORE_API void infer_embed_engine_destroy(InferEmbedEngine *engine);

/*
 * Embed a 256×256 RGB888 image (768 KiB).
 * On success writes *out_dim and returns a heap buffer (free with infer_floats_free).
 */
INFER_CORE_API float *infer_embed_rgb256(
    InferEmbedEngine *engine,
    const uint8_t *rgb256,
    size_t rgb_len,
    size_t *out_dim,
    char **out_error);

/*
 * Embed multiple 256×256 RGB888 images in one batch.
 * rgb_batch: count × 768 KiB concatenated.
 * On success writes *out_count, *out_dim (per vector) and returns count×dim floats
 * (free with infer_floats_free).
 */
INFER_CORE_API float *infer_embed_rgb256_batch(
    InferEmbedEngine *engine,
    const uint8_t *rgb_batch,
    size_t rgb_len,
    size_t count,
    size_t *out_count,
    size_t *out_dim,
    char **out_timings_json,
    char **out_error);

INFER_CORE_API InferIconIndex *infer_icon_index_load(
    InferRegistry *registry,
    const char *pack_id,
    char **out_error);

INFER_CORE_API void infer_icon_index_destroy(InferIconIndex *index);

/*
 * Match one embedding against icon index.
 * On success writes JSON object or null to *out_json and returns 0.
 * JSON shape: {"name":"...","score":0.91} or null
 */
INFER_CORE_API int32_t infer_icon_index_match_embedding(
    InferIconIndex *index,
    const float *embedding,
    size_t dim,
    float min_cosine,
    char **out_json,
    char **out_error);

/*
 * Batch match embeddings against icon index (one index scan for all queries).
 * `embeddings` is row-major: count * dim floats.
 * On success writes JSON array to *out_json and returns 0.
 * JSON shape: [null, {"name":"...","score":0.91}, ...]
 */
INFER_CORE_API int32_t infer_icon_index_match_embeddings_batch(
    InferIconIndex *index,
    const float *embeddings,
    size_t count,
    size_t dim,
    float min_cosine,
    char **out_json,
    char **out_error);

/*
 * Top-k search for one embedding.
 * On success writes JSON array to *out_json and returns 0.
 * JSON shape: [{"name":"...","score":0.91}, ...]
 */
INFER_CORE_API int32_t infer_icon_index_search(
    InferIconIndex *index,
    const float *embedding,
    size_t dim,
    size_t top_k,
    char **out_json,
    char **out_error);


#ifdef __cplusplus
}
#endif

#endif /* INFER_CORE_H */
