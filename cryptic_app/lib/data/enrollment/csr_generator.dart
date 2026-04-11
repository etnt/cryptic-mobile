// lib/data/enrollment/csr_generator.dart
//
// PKCS#10 CSR generation for mTLS enrollment.
//
// Generates an RSA-2048 keypair and a self-signed CSR with CN=username.
// The CSR is PEM-encoded for submission to the Cryptic CA.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart' as pc;

/// Result of CSR generation — contains the CSR PEM and the TLS private key PEM.
class CsrResult {
  const CsrResult({
    required this.csrPem,
    required this.privateKeyPem,
  });

  /// The PKCS#10 CSR in PEM format.
  final String csrPem;

  /// The RSA private key in PKCS#8 PEM format.
  final String privateKeyPem;
}

/// Generates RSA keypairs and PKCS#10 Certificate Signing Requests.
class CsrGenerator {
  /// RSA key size in bits.
  static const int _keySize = 2048;

  /// Generate an RSA-2048 keypair and a PKCS#10 CSR for the given username.
  Future<CsrResult> generateCsr(String username) async {
    // Generate RSA keypair
    final keyPair = _generateRsaKeyPair();
    final publicKey = keyPair.publicKey as pc.RSAPublicKey;
    final privateKey = keyPair.privateKey as pc.RSAPrivateKey;

    // Build CSR DER
    final csrDer = _buildCsr(username, publicKey, privateKey);

    // Encode to PEM
    final csrPem = _toPem(csrDer, 'CERTIFICATE REQUEST');
    final privateKeyPem = _toPem(
      _encodePrivateKeyPkcs8(privateKey),
      'PRIVATE KEY',
    );

    return CsrResult(csrPem: csrPem, privateKeyPem: privateKeyPem);
  }

  /// Generate a secure RSA-2048 keypair.
  pc.AsymmetricKeyPair<pc.PublicKey, pc.PrivateKey> _generateRsaKeyPair() {
    final secureRandom = pc.FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), _keySize, 64),
        secureRandom,
      ));

    return keyGen.generateKeyPair();
  }

  /// Build a PKCS#10 CSR in DER format using pointycastle ASN.1 classes.
  Uint8List _buildCsr(
    String username,
    pc.RSAPublicKey publicKey,
    pc.RSAPrivateKey privateKey,
  ) {
    // Subject: CN=username
    final subject = ASN1Name([
      ASN1RDN(ASN1Set(elements: [
        ASN1AttributeTypeAndValue(
          ASN1ObjectIdentifier.fromName('commonName'),
          ASN1UTF8String(utf8StringValue: username),
        ),
      ])),
    ]);

    // SubjectPublicKeyInfo
    final rsaKeySeq = ASN1Sequence(elements: [
      ASN1Integer(publicKey.modulus!),
      ASN1Integer(publicKey.publicExponent!),
    ]);
    final subjectPkInfo = ASN1SubjectPublicKeyInfo(
      ASN1AlgorithmIdentifier.fromIdentifier('1.2.840.113549.1.1.1'),
      ASN1BitString(
        stringValues: Uint8List.fromList([0, ...rsaKeySeq.encode()]),
      ),
    );

    // CertificationRequestInfo
    final certReqInfo = ASN1CertificationRequestInfo(
      ASN1Integer(BigInt.zero), // version 0
      subject,
      subjectPkInfo,
    );

    // Sign the CertificationRequestInfo
    final certReqInfoDer = certReqInfo.encode();
    final signer = pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201');
    signer.init(
      true,
      pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey),
    );
    final signature = signer.generateSignature(certReqInfoDer);

    // Build full CertificationRequest
    final csr = ASN1CertificationRequest(
      certReqInfo,
      ASN1AlgorithmIdentifier.fromIdentifier('1.2.840.113549.1.1.11'),
      ASN1BitString(
        stringValues: Uint8List.fromList([0, ...signature.bytes]),
      ),
    );

    return csr.encode();
  }

  /// Encode RSA private key in PKCS#8 format.
  Uint8List _encodePrivateKeyPkcs8(pc.RSAPrivateKey key) {
    // RSAPrivateKey (PKCS#1)
    final rsaPrivKeySeq = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero), // version
      ASN1Integer(key.modulus!),
      ASN1Integer(key.publicExponent!),
      ASN1Integer(key.privateExponent!),
      ASN1Integer(key.p!),
      ASN1Integer(key.q!),
      ASN1Integer(
        key.privateExponent! % (key.p! - BigInt.one),
      ), // d mod (p-1)
      ASN1Integer(
        key.privateExponent! % (key.q! - BigInt.one),
      ), // d mod (q-1)
      ASN1Integer(key.q!.modInverse(key.p!)), // q^-1 mod p
    ]);

    // PKCS#8 PrivateKeyInfo
    final pkcs8 = ASN1PrivateKeyInfo(
      ASN1Integer(BigInt.zero), // version
      ASN1AlgorithmIdentifier.fromIdentifier('1.2.840.113549.1.1.1'),
      ASN1OctetString(octets: rsaPrivKeySeq.encode()),
    );

    return pkcs8.encode();
  }

  /// Encode DER bytes as PEM with the given label.
  String _toPem(Uint8List der, String label) {
    final b64 = base64.encode(der);
    final lines = <String>['-----BEGIN $label-----'];
    for (var i = 0; i < b64.length; i += 64) {
      final end = (i + 64 < b64.length) ? i + 64 : b64.length;
      lines.add(b64.substring(i, end));
    }
    lines.add('-----END $label-----');
    return lines.join('\n');
  }
}
