# Product Requirements Document: AI-Powered CV Screener

## 1. Overview

An AI-powered tool that lets a recruiter ask natural-language questions about a collection of CVs and get accurate, grounded answers. The system ingests a set of CV PDFs, makes their content retrievable, and answers questions through an LLM in a simple chat interface (a Retrieval-Augmented Generation pipeline).

**Companion doc:** [`tech-prd.md`](tech-prd.md) defines the technical design.

---

## 2. Goals & Success Criteria

| Goal | Success Metric |
|------|---------------|
| Grounded answers | Responses are based on CV content, never hallucinated candidates/facts |
| Complete answers | Listing/counting queries consider the whole candidate pool, not a subset |
| Realistic dataset | 25–30 fake CV PDFs with photo, contact, experience, skills, education |
| Source attribution | Answers can be traced to the specific CV(s) used |
| Graceful handling | No-match and out-of-scope questions handled cleanly |
| Usable chat UI | Type a question, get a readable, relevant answer |

### Non-Goals
- Authentication / accounts
- Cloud deployment (runs locally)
- Runtime CV upload by end users (dataset is pre-generated)
- Persistent chat history across sessions

---

## 3. Personas

| Persona | Need |
|---------|------|
| **Recruiter** (primary) | Fast, trustworthy answers about the candidate pool |
| **Hiring Manager** | Compare and rank candidates against role criteria |

---

## 4. Scope

**In scope:** CV dataset generation; ingestion pipeline (PDF → text → chunks → embeddings → store); RAG backend exposed via API; chat interface with source attribution; in-session follow-up; local execution.

**Out of scope:** authentication, hosting, runtime upload, CV management UI, cross-session history.

---

## 5. Use Cases (Query Catalog)

### 5.1 Single-Attribute Lookup
| ID | Use Case | Example |
|----|----------|---------|
| UC-01 | Skill search | "Who has experience with Python?" |
| UC-02 | Education search | "Which candidate graduated from UPC?" |
| UC-03 | Role/title search | "Who has worked as a Product Manager?" |
| UC-04 | Location search | "Which candidates are based in Barcelona?" |
| UC-05 | Language search | "Who speaks German?" |
| UC-06 | Certification/tool search | "Who is certified in AWS?" |
| UC-07 | Contact lookup | "What is John Smith's email?" |

### 5.2 Candidate-Centric
| ID | Use Case | Example |
|----|----------|---------|
| UC-08 | Profile summary | "Summarize the profile of Jane Doe." |
| UC-09 | Specific detail | "How many years of experience does Jane Doe have?" |
| UC-10 | Work history | "Where has Jane Doe worked?" |

### 5.3 Multi-Criteria & Filtering
| ID | Use Case | Example |
|----|----------|---------|
| UC-11 | Combined criteria | "Who knows Python AND has a Master's degree?" |
| UC-12 | Experience threshold | "Who has more than 5 years of experience?" |
| UC-13 | Negation | "Which candidates do NOT have management experience?" |

### 5.4 Aggregation & Ranking
| ID | Use Case | Example |
|----|----------|---------|
| UC-14 | Count | "How many candidates know React?" |
| UC-15 | Ranking | "Who are the top 3 candidates for a backend role?" |
| UC-16 | Best fit | "Which candidate best fits a data scientist role?" |

### 5.5 Comparative
| ID | Use Case | Example |
|----|----------|---------|
| UC-17 | Compare two | "Compare Jane Doe and John Smith." |
| UC-18 | Differentiator | "Who has more cloud experience, A or B?" |

### 5.6 Conversational / Follow-up
| ID | Use Case | Example |
|----|----------|---------|
| UC-19 | Follow-up pronoun | (after UC-08) "What about her education?" |
| UC-20 | Refinement | (after UC-01) "Of those, who also knows Django?" |

### 5.7 Guardrail Cases
| ID | Use Case | Expected |
|----|----------|----------|
| UC-21 | Unrelated question ("What's the weather?") | Politely decline; scope is CVs only |
| UC-22 | No matching candidate ("Who knows COBOL?", none do) | State clearly that no candidate matches |
| UC-23 | Hallucination bait (invented candidate) | Do not invent; state no such candidate |
| UC-24 | Ambiguous name (multiple "John"s) | Clarify or list all matches |
| UC-25 | Subjective/discriminatory ("How old is X?") | Decline; answer only on factual CV content |

---

## 6. Functional Requirements

### 6.1 CV Generation
| ID | Requirement | Priority |
|----|-------------|----------|
| CV-01 | Generate 25–30 unique, fake CVs in PDF format | Must |
| CV-02 | Each CV includes AI-generated photo, name, contact, experience, skills, education | Must |
| CV-03 | Diverse roles, seniorities, industries, languages | Must |
| CV-04 | Text and images generated via LLM / image model | Must |
| CV-05 | Internally consistent data (experience years align with dates) | Should |
| CV-06 | Reproducible (seeded) generation script | Should |
| CV-07 | Some shared skills/schools so filtering queries are meaningful | Should |
| CV-08 | ≥1 duplicate first name to exercise disambiguation (UC-24) | Could |
| CV-09 | Seed canonical entities (a "Jane Doe", a UPC graduate, several Python candidates) | Must |

### 6.2 Ingestion Pipeline
| ID | Requirement | Priority |
|----|-------------|----------|
| ING-01 | Extract text from the CV PDFs | Must |
| ING-02 | Handle PDFs with little/no extractable text (fallback) | Should |
| ING-03 | Chunk text with candidate + section metadata | Must |
| ING-04 | Generate embeddings per chunk | Must |
| ING-05 | Store embeddings + metadata | Must |
| ING-06 | Idempotent / re-runnable ingestion | Should |
| ING-07 | Per-file ingestion status (success/skipped/failed) | Should |

### 6.3 RAG Backend
| ID | Requirement | Priority |
|----|-------------|----------|
| RAG-01 | Retrieve relevant CV content for a query | Must |
| RAG-02 | Pass context + query to the LLM to answer | Must |
| RAG-03 | Answers grounded only in CV data; no invented candidates/facts | Must |
| RAG-04 | Say so when the answer is not in the CVs | Must |
| RAG-05 | Return source metadata (which CV(s) used) | Should |
| RAG-06 | Expose a clean API endpoint for the frontend | Must |
| RAG-07 | Incorporate prior turns for follow-ups | Should |
| RAG-08 | Listing/aggregation queries consider the whole corpus (completeness) | Must |
| RAG-09 | Treat CV text as data, not instructions (prompt-injection defense) | Should |
| RAG-10 | Configurable model and API key via environment | Must |

### 6.4 Chat Interface
| ID | Requirement | Priority |
|----|-------------|----------|
| UI-01 | Single-page chat UI: text input + answer display | Must |
| UI-02 | Readable, conversational response rendering | Must |
| UI-03 | Loading indicator while awaiting a response | Should |
| UI-04 | Show which CV(s) were used as sources | Should |
| UI-05 | Session chat history visible | Should |
| UI-06 | Friendly error messages on backend failure | Must |
| UI-07 | Block empty queries; handle long inputs | Should |
| UI-08 | Clear/reset the conversation | Could |
| UI-10 | Enter-to-send; disabled input while a request is in flight | Should |

---

## 7. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Runs locally; only external dependency is the LLM/embedding API |
| NFR-02 | Typical query answered in < 10 seconds |
| NFR-04 | A single malformed CV does not break ingestion of the rest |
| NFR-05 | API/network failures surface as handled errors, not crashes |
| NFR-06 | Clean structure, separation of concerns, documented modules |
| NFR-08 | Respects API rate limits; batches embeddings |
| NFR-09 | Model, top-k, chunk settings configurable |
| NFR-10 | Backend logs queries, retrieval, and errors |
| NFR-11 | API keys never committed; loaded from `.env` |

---

## 8. Error Handling & Edge Cases

| ID | Scenario | Handling |
|----|----------|----------|
| ERR-01 | LLM API timeout / rate limit | Retry with backoff; friendly error if still failing |
| ERR-02 | Invalid/missing API key | Fail fast at startup with a clear message |
| ERR-03 | Empty query | Frontend blocks; backend rejects |
| ERR-04 | No relevant matches | "No candidate matches" rather than fabrication |
| ERR-05 | Corrupt/unreadable PDF | Skip, log, continue |
| ERR-06 | Image-only PDF (no text layer) | Fallback path or flag |
| ERR-07 | Index not built | Clear "knowledge base not initialized" error |
| ERR-08 | Extremely long input | Truncate or reject with guidance |
| ERR-09 | Prompt injection inside a CV | Treated as data, not instructions |
| ERR-10 | Ambiguous candidate reference | Clarify or enumerate matches |

---

## 9. Data Model (per stored chunk)

| Field | Description |
|-------|-------------|
| `chunkId` | Stable unique id (idempotency) |
| `candidateName` | Name parsed from the CV |
| `sourceFile` | Original PDF filename |
| `section` | summary / experience / education / skills / languages / contact |
| `text` | Chunk text |
| `embedding` | Vector representation |

---

## 10. Acceptance Criteria

- [ ] 25–30 fake CV PDFs exist, each with photo, contact, experience, skills, education
- [ ] Ingestion builds the index from all CVs with per-file status output
- [ ] Canonical queries return correct, grounded answers:
  - [ ] "Who has experience with Python?"
  - [ ] "Which candidate graduated from UPC?"
  - [ ] "Summarize the profile of Jane Doe."
- [ ] A counting query returns a correct, complete count (e.g. "How many know React?")
- [ ] Out-of-scope and no-match queries are handled cleanly (UC-21, UC-22)
- [ ] Source attribution is shown for answers
- [ ] Runs locally per the README; API key loaded from env and not committed

---

## 11. Assumptions & Open Defaults

- The CV dataset is synthetic; no real-PII handling required.
- Single local user; no concurrency at scale expected.
- English-majority CVs; candidates may vary language.
- Source attribution and CV-only grounding are treated as core (they materially improve answer trust).
