package com.menuqr.infrastructure.ml;

import com.menuqr.infrastructure.storage.S3ClientFactory;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.util.Arrays;
import java.util.Optional;

/**
 * Descarga opcional del artefacto de modelo (p. ej. ONNX) desde S3 al arranque.
 * La inferencia sigue siendo mock en {@link com.menuqr.application.menu.RecommendMenuItemsUseCase};
 * los bytes quedan disponibles para integrar ONNX Runtime u otra librería después.
 */
@ApplicationScoped
public class RecommendationModelLoader {

    private static final Logger LOG = Logger.getLogger(RecommendationModelLoader.class);

    @Inject
    S3ClientFactory s3ClientFactory;

    @ConfigProperty(name = "recommendations.model.s3.bucket")
    Optional<String> modelBucket;

    @ConfigProperty(name = "recommendations.model.s3.key")
    Optional<String> modelKey;

    private volatile byte[] modelBytes = new byte[0];

    @PostConstruct
    void loadFromS3IfConfigured() {
        String bucket = modelBucket.map(String::trim).filter(s -> !s.isEmpty()).orElse(null);
        String key = modelKey.map(String::trim).filter(s -> !s.isEmpty()).orElse(null);
        if (bucket == null || key == null) {
            LOG.debug("Recommendation model S3 not configured (set recommendations.model.s3.bucket and .key)");
            return;
        }

        try (S3Client s3 = s3ClientFactory.createClient()) {
            var response = s3.getObjectAsBytes(
                GetObjectRequest.builder().bucket(bucket).key(key).build()
            );
            byte[] bytes = response.asByteArray();
            if (bytes.length == 0) {
                LOG.warnf("Recommendation model object is empty: s3://%s/%s", bucket, key);
                return;
            }
            this.modelBytes = bytes;
            LOG.infof("Recommendation model loaded from s3://%s/%s (%d bytes)", bucket, key, bytes.length);
        } catch (NoSuchKeyException e) {
            LOG.errorf(e, "Recommendation model not found: s3://%s/%s", bucket, key);
        } catch (Exception e) {
            LOG.errorf(e, "Failed to load recommendation model from s3://%s/%s", bucket, key);
        }
    }

    /** true si se cargaron bytes (incluido tras fallo parcial: solo true si length &gt; 0). */
    public boolean isLoaded() {
        return modelBytes.length > 0;
    }

    public int byteSize() {
        return modelBytes.length;
    }

    /**
     * Copia defensiva del buffer; vacío si no hay modelo cargado.
     */
    public Optional<byte[]> modelBytes() {
        if (modelBytes.length == 0) {
            return Optional.empty();
        }
        return Optional.of(Arrays.copyOf(modelBytes, modelBytes.length));
    }
}
