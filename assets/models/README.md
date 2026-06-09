# On-device ML models

Drop a TFLite segmentation model here as `cutout.tflite` to enable real
ML-based subject cutout. Until then, the app falls back to the classical
(model-free) cutout algorithm automatically.

Recommended models (use a permissively-licensed export):
- U^2-Net (portrait/salient-object matting) exported to .tflite
- MODNet (portrait matting) exported to .tflite

Expected I/O (handled by TfliteSegmenter; adjust there if your model differs):
- Input:  1 x H x W x 3, float32, normalized to [0,1] (or [-1,1])
- Output: 1 x H x W x 1 alpha matte, float32 in [0,1]
