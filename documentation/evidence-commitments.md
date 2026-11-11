# Evidence commitments

This guide is for people who compare evidence records across systems. You will learn what an evidence commitment can establish and how it relates to the EU AI Act.

An evidence commitment is a digest of protocol-defined evidence content. It lets a verifier detect whether that content differs from the value named by the commitment. A digest alone does not establish who supplied the content or whether the content is true.

## Evidence in Agent Blueprint Protocol

The protocol defines portable artifacts, commitments, and verification results. A successful reconciliation returns typed checks and an explicit `not_verified` list. The result is not a log, compliance record, or compliance assessment.

The protocol does not record runtime events. Hosts choose and operate their own logging and evidence systems.

## EU AI Act context

The EU AI Act requires high-risk AI systems to allow automatic event recording over the system's lifetime. Providers keep generated logs to the extent they control them. Deployers keep logs under their control for a period appropriate to the system's purpose. The period is at least six months unless applicable Union or national law provides otherwise. Data protection law may affect that period. See Articles 12, 19, and 26(6) of [Regulation (EU) 2024/1689](https://eur-lex.europa.eu/eli/reg/2024/1689/oj/eng).

Article 25(4) requires a written agreement when a third party supplies an AI system, AI model, tool, service, component, or process used in a high-risk AI system. The agreement specifies needed information, capabilities, technical access, and assistance. The exception covers third parties that make tools, services, processes, or components public under a free and open-source license. It does not cover general-purpose AI models.

Regulation (EU) 2026/1744 sets the application dates for Chapter III, Sections 1 to 3, except Article 6(5). Those sections apply from December 2, 2027 for high-risk systems classified under Article 6(2) and Annex III. They apply from August 2, 2028 for systems classified under Article 6(1) and Annex I. See [Article 1(40) of Regulation (EU) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj/eng).

These obligations concern the systems and operators defined by the law. A Blueprint or evidence commitment does not satisfy them.

## Next steps

- [Read the evidence guide](reading-evidence.md)
- [Review the security model](security-model.md)
- [Read protocol sections 13 and 18](../spec/protocol.md#13-evidence-and-reconcile)
