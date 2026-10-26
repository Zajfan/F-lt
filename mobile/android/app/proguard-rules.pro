# SQLCipher is loaded through JNI. Keep its native bridge and metadata when
# release shrinking is enabled by Flutter/AGP.
-keep class net.sqlcipher.** { *; }
