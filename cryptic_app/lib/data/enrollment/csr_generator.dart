// lib/data/enrollment/csr_generator.dart
//
// PKCS#10 CSR generation for mTLS enrollment using ECDSA P-256.
//
// Generates an ECDSA P-256 keypair and a PKCS#10 CSR with CN=username.
// P-256 is used because it has universal TLS stack support (BoringSSL,
// OpenSSL, Erlang OTP SSL) unlike Ed25519 which lacks mTLS support
// in some implementations.

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

  /// The ECDSA private key in PKCS#8 PEM format.
  final String privateKeyPem;
}

/// Generates ECDSA P-256 keypairs and PKCS#10 Certificate Signing Requests.
class CsrGenerator {
  /// OID for id-ecPublicKey (1.2.840.10045.2.1)
  static const String _ecPublicKeyOid = '1.2.840.10045.2.1';

  /// OID for secp256r1 / P-256 (1.2.840.10045.3.1.7)
  static const String _secp256r1Oid = '1.2.840.10045.3.1.7';

  /// OID for ecdsa-with-SHA256 (1.2.840.10045.4.3.2)
  static const String _ecdsaSha256Oid = '1.2.840.10045.4.3.2';

  /// Generate an ECDSA P-256 keypair and a PKCS#10 CSR for the given username.
  Future<CsrResult> generateCsr(String username) async {
    final keyPair = _generateEcKeyPair();
    final publicKey = keyPair.publicKey as pc.ECPublicKey;
    final privateKey = keyPair.privateKey as pc.ECPrivateKey;

    final csrDer = _buildCsr(username, publicKey, privateKey);

    final csrPem = _toPem(csrDer, 'CERTIFICATE REQUEST');
    final privateKeyPem = _toPem(
      _encodePrivateKeyPkcs8(privateKey, publicKey),
      'PRIVATE KEY',
    );

    return CsrResult(csrPem: csrPem, privateKeyPem: privateKeyPem);
  }

  pc.AsymmetricKeyPair<pc.PublicKey, pc.PrivateKey> _generateEcKeyPair() {
    final secureRandom = pc.FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));

    final params = pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1());
    final keyGen = pc.ECKeyGenerator()
      ..init(pc.ParametersWithRandom(params, secureRandom));

    return keyGen.generateKeyPair();
  }

  pc.SecureRandom _createSecureRandom() {
    final secureRandom = pc.FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  /// Build a PKCS#10 CSR in DER format.
  Uint8List _buildCsr(
    String username,
    pc.ECPublicKey publicKey,
    pc.ECPrivateKey privateKey,
  ) {
    final ecPubOid =
        ASN1ObjectIdentifier.fromIdentifierString(_ecPublicKeyOid);
    final curveOid =
        ASN1ObjectIdentifier.fromIdentifierString(_secp256r1Oid);

    // AlgorithmIdentifier: SEQUENCE { ecPublicKey OID, secp256r1 OID }
    final algIdSeq = ASN1Sequence(elements: [ecPubOid, curveOid]);

    // Subject: CN=username
    final subject = ASN1Sequence(elements: [
      ASN1Set(elements: [
        ASN1Sequence(elements: [
          ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'),
          ASN1UTF8String(utf8StringValue: username),
        ]),
      ]),
    ]);

    // Public key: uncompressed EC point (04 || X || Y)
    final ecPoint = publicKey.Q!.getEncoded(false);
    final subjectPkInfo = ASN1Sequence(elements: [
      algIdSeq,
      ASN1BitString(stringValues: ecPoint),
    ]);

    // CertificationRequestInfo inner SEQUENCE
    final certReqInfoInner = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      subject,
      subjectPkInfo,
    ]);

    // Append [0] IMPLICIT empty attributes (A0 00)
    final certReqInfoDer = _appendEmptyAttributes(certReqInfoInner.encode());

    // Sign with ECDSA-SHA256
    final signer = pc.ECDSASigner(pc.SHA256Digest());
    signer.init(
      true,
      pc.ParametersWithRandom(
        pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey),
        _createSecureRandom(),
      ),
    );
    final ecSig =
        signer.generateSignature(certReqInfoDer) as pc.ECSignature;

    // DER-encode ECDSA signature: SEQUENCE { INTEGER r, INTEGER s }
    final sigDer = ASN1Sequence(elements: [
      ASN1Integer(ecSig.r),
      ASN1Integer(ecSig.s),
    ]).encode();

    // Signature algorithm: ecdsa-with-SHA256
    final sigAlgOid =
        ASN1ObjectIdentifier.fromIdentifierString(_ecdsaSha256Oid);
    final sigAlgSeq = ASN1Sequence(elements: [sigAlgOid]);

    // Full CertificationRequest
    final csr = ASN1Sequence();
    csr.add(ASN1Object.fromBytes(certReqInfoDer));
    csr.add(sigAlgSeq);
    csr.add(ASN1BitString(stringValues: sigDer));

    return csr.encode();
  }

  /// Append an empty [0] IMPLICIT SET OF Attribute to a SEQUENCE's DER.
  Uint8List _appendEmptyAttributes(Uint8List seqDer) {
    var offset = 1; // skip tag byte (0x30)
    int contentLen;
    if (seqDer[offset] < 0x80) {
      contentLen = seqDer[offset];
      offset += 1;
    } else {
      final lenBytes = seqDer[offset] & 0x7F;
      contentLen = 0;
      for (var i = 0; i < lenBytes; i++) {
        contentLen = (contentLen << 8) | seqDer[offset + 1 + i];
      }
      offset += 1 + lenBytes;
    }

    final content = seqDer.sublist(offset, offset + contentLen);
    final newContent = Uint8List(content.length + 2);
    newContent.setRange(0, content.length, content);
    newContent[content.length] = 0xA0; // [0] context tag, constructed
    newContent[content.length + 1] = 0x00; // length 0

    return _wrapInSequence(newContent);
  }

  Uint8List _wrapInSequence(Uint8List content) {
    final lenBytes = _encodeDerLength(content.length);
    final result = Uint8List(1 + lenBytes.length + content.length);
    result[0] = 0x30;
    result.setRange(1, 1 + lenBytes.length, lenBytes);
    result.setRange(1 + lenBytes.length, result.length, content);
    return result;
  }

  Uint8List _encodeDerLength(int length) {
    if (length < 0x80) {
      return Uint8List.fromList([length]);
    } else if (length < 0x100) {
      return Uint8List.fromList([0x81, length]);
    } else if (length < 0x10000) {
      return Uint8List.fromList([0x82, length >> 8, length & 0xFF]);
    } else {
      return Uint8List.fromList([
        0x83,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ]);
    }
  }

  /// Encode EC private key in PKCS#8 format.
  ///
  /// PrivateKeyInfo ::= SEQUENCE {
  ///   version INTEGER (0),
  ///   algorithm AlgorithmIdentifier { ecPublicKey, secp256r1 },
  ///   privateKey OCTET STRING { ECPrivateKey }
  /// }
  Uint8List _encodePrivateKeyPkcs8(
    pc.ECPrivateKey privateKey,
    pc.ECPublicKey publicKey,
  ) {
    final ecPubOid =
        ASN1ObjectIdentifier.fromIdentifierString(_ecPublicKeyOid);
    final curveOid =
        ASN1ObjectIdentifier.fromIdentifierString(_secp256r1Oid);

    final algId = ASN1Sequence(elements: [ecPubOid, curveOid]);

    // ECPrivateKey ::= SEQUENCE {
    //   version INTEGER (1),
    //   privateKey OCTET STRING,
    //   [1] publicKey BIT STRING OPTIONAL
    // }
    final privKeyBytes = _bigIntToFixedBytes(privateKey.d!, 32);
    final ecPoint = publicKey.Q!.getEncoded(false);

    // [1] EXPLICIT BIT STRING for public key
    final pubKeyBitString = ASN1BitString(stringValues: ecPoint);
    final pubKeyTagged = ASN1Object(tag: 0xA1);
    pubKeyTagged.valueBytes = pubKeyBitString.encode();

    final ecPrivKey = ASN1Sequence(elements: [
      ASN1Integer(BigInt.one),
      ASN1OctetString(octets: privKeyBytes),
      pubKeyTagged,
    ]);

    final pkcs8 = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      algId,
      ASN1OctetString(octets: ecPrivKey.encode()),
    ]);

    return pkcs8.encode();
  }

  /// Convert BigInt to fixed-length big-endian bytes.
  Uint8List _bigIntToFixedBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

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
