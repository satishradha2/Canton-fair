import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.Key;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.util.Arrays;
import java.util.Base64;
import java.util.Properties;

/** Validates private-key recovery without logging credentials. Requires Java 17+. */
class ValidateAndroidSigning {
    public static void main(String[] args) {
        try {
            validate(args);
        } catch (Exception error) {
            System.err.println("Release signing validation failed. Check that the keystore, alias, store password and private-key password belong together. No signing key was changed.");
            System.exit(1);
        }
    }

    private static void validate(String[] args) throws Exception {
        Properties values = new Properties();
        Path keystore;
        if (args.length > 0) {
            Path propertiesFile = Path.of(args[0]).toAbsolutePath();
            try (InputStream input = Files.newInputStream(propertiesFile)) {
                values.load(input);
            }
            keystore = propertiesFile.getParent().resolve(required(values.getProperty("storeFile")));
        } else {
            keystore = Path.of(required(System.getenv("ANDROID_KEYSTORE_FILE")));
            values.setProperty("storePassword", required(System.getenv("ANDROID_KEYSTORE_PASSWORD")));
            values.setProperty("keyPassword", required(System.getenv("ANDROID_KEY_PASSWORD")));
            values.setProperty("keyAlias", required(System.getenv("ANDROID_KEY_ALIAS")));
        }
        char[] storePassword = required(values.getProperty("storePassword")).toCharArray();
        char[] keyPassword = required(values.getProperty("keyPassword")).toCharArray();
        try {
            KeyStore store = KeyStore.getInstance(keystore.toFile(), storePassword);
            String alias = required(values.getProperty("keyAlias"));
            Key key = store.getKey(alias, keyPassword);
            if (!(key instanceof PrivateKey)) throw new IllegalStateException();
            String algorithm = switch (key.getAlgorithm()) {
                case "RSA" -> "SHA256withRSA";
                case "EC" -> "SHA256withECDSA";
                case "DSA" -> "SHA256withDSA";
                default -> throw new IllegalStateException();
            };
            byte[] challenge = "Canton Fair signing validation".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            Signature proof = Signature.getInstance(algorithm);
            proof.initSign((PrivateKey) key);
            proof.update(challenge);
            byte[] signed = proof.sign();
            proof.initVerify(store.getCertificate(alias));
            proof.update(challenge);
            if (!proof.verify(signed)) throw new IllegalStateException();
            String fingerprint = java.util.HexFormat.ofDelimiter(":").withUpperCase().formatHex(
                MessageDigest.getInstance("SHA-256").digest(store.getCertificate(alias).getEncoded()));
            if (args.length == 2) {
                String exported = "ANDROID_KEYSTORE_BASE64=" + Base64.getEncoder().encodeToString(Files.readAllBytes(keystore)) + "\n"
                    + "ANDROID_KEYSTORE_PASSWORD=" + values.getProperty("storePassword") + "\n"
                    + "ANDROID_KEY_PASSWORD=" + values.getProperty("keyPassword") + "\n"
                    + "ANDROID_KEY_ALIAS=" + alias + "\n";
                if (values.values().stream().anyMatch(value -> value.toString().contains("\n") || value.toString().contains("\r"))) {
                    throw new IllegalArgumentException();
                }
                Files.writeString(Path.of(args[1]), exported);
            }
            System.out.println("Release signing verified (private key and certificate match).");
            System.out.println("Certificate SHA-256: " + fingerprint);
        } finally {
            Arrays.fill(storePassword, '\0');
            Arrays.fill(keyPassword, '\0');
        }
    }

    private static String required(String value) {
        if (value == null || value.isEmpty()) throw new IllegalArgumentException();
        return value;
    }
}
