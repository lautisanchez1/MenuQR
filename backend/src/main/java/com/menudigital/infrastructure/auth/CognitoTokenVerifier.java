package com.menudigital.infrastructure.auth;

import io.smallrye.jwt.auth.principal.JWTAuthContextInfo;
import io.smallrye.jwt.auth.principal.JWTParser;
import io.smallrye.jwt.auth.principal.ParseException;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.jwt.JsonWebToken;

@ApplicationScoped
public class CognitoTokenVerifier {

    @Inject
    JWTParser parser;

    @ConfigProperty(name = "cognito.issuer-url", defaultValue = "")
    String issuerUrl;

    @ConfigProperty(name = "cognito.client-id", defaultValue = "")
    String clientId;

    private volatile JWTAuthContextInfo contextInfo;

    public boolean isConfigured() {
        return !issuerUrl.isBlank() && !clientId.isBlank();
    }

    public JsonWebToken verify(String token) throws ParseException {
        if (!isConfigured()) {
            throw new ParseException("Cognito is not configured (set COGNITO_ISSUER_URL and COGNITO_CLIENT_ID)");
        }
        return parser.parse(token, contextInfo());
    }

    public String expectedClientId() {
        return clientId;
    }

    private JWTAuthContextInfo contextInfo() {
        JWTAuthContextInfo cached = contextInfo;
        if (cached == null) {
            cached = new JWTAuthContextInfo();
            cached.setIssuedBy(issuerUrl);
            cached.setPublicKeyLocation(issuerUrl + "/.well-known/jwks.json");
            contextInfo = cached;
        }
        return cached;
    }
}
