// lib/domain/services/crypto/crypto_services.dart
//
// Crypto services barrel file - exports all crypto services
//
// Note: Crypto primitives are implemented in lib/data/crypto/
// This file provides domain-level service abstractions if needed.
library crypto_services;

// Crypto primitives are exposed through the data layer:
// - lib/data/crypto/primitives/ - Low-level crypto operations
// - lib/data/crypto/x3dh/ - X3DH key agreement
// - lib/data/crypto/ratchet/ - Double Ratchet protocol
// - lib/data/crypto/keys/ - Key management
