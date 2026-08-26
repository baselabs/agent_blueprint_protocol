# FAQ

**Does a green verification authorize anything?**
No. Every result is structural evidence. Identity, tenancy, live
policy, effect ownership, execution, billing, and evaluation truth are
host-owned surfaces; the Evidence record names them in `not_verified`.

**Why canonical-first decoding?**
Digests are only meaningful over exact bytes. Non-canonical bytes deny
before any semantic read, so two spellings of the same value cannot
both be "the artifact".

**What happens to extensions I don't know?**
Optional extensions quarantine: retained byte-exactly, typed as
unscanned, never executed. Critical ones deny — an unknown critical
surface is a surface you cannot enforce.

**Can I widen a bound for a special case?**
No. Effective bounds never widen host policy. Narrow, clamp with
evidence, or deny — the algebra is property-tested.

**Why is the registry compiled in?**
Registry content is a code release: drift between shipped code and a
shipped registry file would be unrepresentable. The
governance-canonical json is bound to both compiled twins by the
registry-equality gate.

**How do I run the corpus in my own language?**
The runner protocol ships as verifier/RUNNER.md: corpus layout,
load-time integrity, the report format, and the byte-agreement
contract. The standalone kit (verifier + corpus) is attached to every
release tag.
