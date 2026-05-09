package com.menuqr.infrastructure.storage;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.InputStream;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
public class S3ImageStorageService {

    @Inject
    S3ClientFactory s3ClientFactory;
    
    @ConfigProperty(name = "aws.s3.bucket", defaultValue = "menuqr-images")
    String bucketName;
    
    @ConfigProperty(name = "aws.s3.region", defaultValue = "us-east-1")
    String region;
    
    @ConfigProperty(name = "aws.s3.public-url")
    Optional<String> publicUrl;
    
    public String upload(InputStream inputStream, String contentType, long contentLength, String tenantId) {
        String key = "menus/" + tenantId + "/" + UUID.randomUUID() + getExtension(contentType);
        
        S3Client s3Client = s3ClientFactory.createClient();
        
        try {
            PutObjectRequest request = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType(contentType)
                .build();
            
            s3Client.putObject(request, RequestBody.fromInputStream(inputStream, contentLength));
            
            if (publicUrl.isPresent() && !publicUrl.get().isBlank()) {
                return publicUrl.get() + "/" + bucketName + "/" + key;
            }
            
            if (s3Client.serviceClientConfiguration().endpointOverride().isPresent()) {
                var base = s3Client.serviceClientConfiguration().endpointOverride().get().toString().replaceAll("/$", "");
                return base + "/" + bucketName + "/" + key;
            }
            
            return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, key);
        } finally {
            s3Client.close();
        }
    }
    
    private String getExtension(String contentType) {
        return switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/gif" -> ".gif";
            case "image/webp" -> ".webp";
            default -> "";
        };
    }
}
