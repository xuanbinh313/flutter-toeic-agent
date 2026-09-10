// Prompts ported from jun-edu's ImportQuestionsAgentViewModel and
// ImportQuestionsViewModel. Keep the part-specific schemas and note rules aligned.
class ImportQuestionsAgentPrompts {
  ImportQuestionsAgentPrompts._();

  static String forPart(int part) => switch (part) {
    1 => _part1,
    2 => _part2,
    3 => _part3,
    4 => _part4,
    _ => _reading,
  };

  static const _part1 = r'''
Analyze ONLY TOEIC Listening Part 1 (Photographs).
OUTPUT CONSTRAINT: Output ONLY one raw JSON object. No markdown, no code fences, no explanations.
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)

The attached transcript pages are TOEIC Part 1 audio transcript pages.
Do NOT infer or create Part 2, Part 3, or Part 4 questions.
Use question numbers in transcript order, starting from 1 unless printed/spoken numbers are visible.

Return this schema:
{
  "contexts": [
    {
      "id": "p1_q1",
      "part": 1,
      "context_type": "IMAGE_DIAGRAM",
      "content": {"text": ""},
      "index": 0,
      "additional_meta": {"audio_start": 0.0, "audio_end": 0.0, "note": ""},
      "questions": [
        {
          // CRITICAL: This array MUST contain exactly ONE question object for this specific photo.
          "question_number": 1,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Look at the picture and choose the statement that best describes it.",
          "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
          "correct_answer": "Required get from answer sheet image",
          "additional_meta": {
              "note": "REQUIRED. Strictly format this field exactly as follows:
[Translation of the question content stem into Vietnamese (vn)]
[Translation of option 1 into Vietnamese (vn)]
[Translation of option 2 into Vietnamese (vn)]
[Translation of option 3 into Vietnamese (vn)]
[Translation of option 4 into Vietnamese (vn) (if applicable)]

[Detailed grammatical/contextual explanation in Vietnamese (vn) explaining why the correct_answer is right based on keywords from the transcript.]"
          }
        }
      ]
    }
  ]
}

STRICT PART 1 RULES:
1. Every context_type must be "IMAGE_DIAGRAM".
2. ONE RELATIONSHIP ONLY: For each attached photograph/transcript question, you must create a SEPARATE context object in the "contexts" array. 
3. NO GROUPING: The "questions" array inside ANY context object MUST contain exactly ONE (1) question object. NEVER place multiple questions inside a single context's "questions" array.
4. If there are 10 photos in the transcript, the final "contexts" array must contain exactly 10 distinct context objects, each containing exactly 1 question.
5. Every options array must be a flat string array. Stripped of prefixes like (A), B., C), etc. Keep original transcript order.
6. Do not use question numbers 11, 12, 13, 14 unless those exact numbers are visibly printed on the image.
7. Do not create spoken question-response content. That belongs to Part 2, not Part 1.
8. Only take questions from 1 to 10.
''';

  static const _part2 = r'''
Analyze ONLY TOEIC Listening Part 2 (Question-Response).
OUTPUT CONSTRAINT: Output ONLY one raw JSON object. No markdown, no code fences, no explanations.
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)

CARDINAL STRUCTURAL RULES:
1. Extract all questions from Question 11 to Question 40.
2. The root "contexts" array MUST contain exactly ONE element per question (e.g., 30 context objects for questions 11 through 40).
3. EVERY context object in "contexts" must have:
   - "id": "p2_q{question_number}" (e.g., "p2_q11", "p2_q12", ..., "p2_q40")
   - "context_type": "STANDALONE"
   - "questions": An array containing EXACTLY ONE question object (length = 1). NEVER put multiple questions in one context object.

Return strictly this JSON structure format:
{
  "contexts": [
    {
      "id": "p2_q11",
      "part": 2,
      "context_type": "STANDALONE",
      "content": {"text": "Mark your answer on your answer sheet"},
      "index": 0,
      "additional_meta": {"audio_start": 0.0, "audio_end": 0.0, "note": ""},
      "questions": [
        {
          "question_number": 11,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Spoken question 11 text...",
          "options": ["Response A", "Response B", "Response C"],
          "correct_answer": "Extract from answer key",
          "additional_meta": {
            "note": "[Dịch câu hỏi Q11 sang tiếng Việt]\n[Dịch đáp án A]\n[Dịch đáp án B]\n[Dịch đáp án C]\n\n[Giải thích chi tiết ngữ pháp/ngữ cảnh bằng tiếng Việt]"
          }
        }
      ]
    },
    {
      "id": "p2_q12",
      "part": 2,
      "context_type": "STANDALONE",
      "content": {"text": "Mark your answer on your answer sheet"},
      "index": 1,
      "additional_meta": {"audio_start": 0.0, "audio_end": 0.0, "note": ""},
      "questions": [
        {
          "question_number": 12,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Spoken question 12 text...",
          "options": ["Response A", "Response B", "Response C"],
          "correct_answer": "Extract from answer key",
          "additional_meta": {
            "note": "[Dịch câu hỏi Q12 sang tiếng Việt]\n[Dịch đáp án A]\n[Dịch đáp án B]\n[Dịch đáp án C]\n\n[Giải thích chi tiết ngữ pháp/ngữ cảnh bằng tiếng Việt]"
          }
        }
      ]
    }
  ]
}

''';

  static const _part3 = r'''
Analyze ONLY TOEIC Listening Part 3 (Conversations).
OUTPUT CONSTRAINT: Output ONLY one raw JSON object. No markdown, no code fences, no explanations.
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)

The attached pages contain Part 3 question pages and/or transcript pages.
Do NOT infer or create Part 1, Part 2, or Part 4 questions.

Transcript grouping labels are authoritative. In transcript pages, labels such as
"41-43 refer to the following conversation" or "Questions 41-43 refer to..."
mean that questions 41, 42, and 43 must share exactly one AUDIO_SRT context.
Use the full transcript text following that label as that context's content.text.
Create a new context when the next start-number/range label appears.

Return this schema:
{
  "contexts": [
    {
      "id": "p3_41_43",
      "part": 3,
      "context_type": "AUDIO_SRT",
      "content": {"text": "Full conversation transcript for questions 41-43."},
      "index": 0,
      "additional_meta": {"audio_start": 0.0, "audio_end": 0.0, "note": "REQUIRED. Vietnamese translation of the transcript. not translate summary transcript."},
      "questions": [
        {
          "question_number": 41,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Printed Part 3 question stem.",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correct_answer": "",
          "additional_meta": {"note": "REQUIRED. Vietnamese translation of the question stem, Vietnamese translation of options A-D, blank line, then Vietnamese explanation using conversation keywords."}
        },
        {
          "question_number": 42,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Printed Part 3 question stem.",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correct_answer": "",
          "additional_meta": {"note": "REQUIRED. Vietnamese translation of the question stem, Vietnamese translation of options A-D, blank line, then Vietnamese explanation using conversation keywords."}
        }
      ]
    }
  ]
}

STRICT PART 3 RULES:
1. Every context part must be 3.
2. Every context_type must be AUDIO_SRT.
3. MUST take all questions from 41 to 70.
4. Questions sharing one conversation must be nested in the same context's questions array.
5. Extract only Part 3 conversation questions.
6. Preserve printed question numbers when visible.
7. Use transcript start-number/range labels to group questions; do not split questions from one label into separate contexts.
8. If a label says 41-43, only questions 41, 42, and 43 may reference that context.
9. The top-level JSON object must contain exactly one "contexts" array; do not add a top-level "questions" array.
10. Do not return nested groups, markdown tables, CSV, or any schema other than the JSON object above.
11. Never leave contexts.additional_meta.note or questions.additional_meta.note empty.
''';

  static const _part4 = r'''
Analyze ONLY TOEIC Listening Part 4 (Talks).
OUTPUT CONSTRAINT: Output ONLY one raw JSON object. No markdown, no code fences, no explanations.
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)

The attached pages contain Part 4 question pages and/or transcript pages.
Do NOT infer or create Part 1, Part 2, or Part 3 questions.

Transcript grouping labels are authoritative. In transcript pages, labels such as
"71-73 refer to the following talk" or "Questions 71-73 refer to..."
mean that questions 71, 72, and 73 must share exactly one AUDIO_SRT context.
Use the full transcript text following that label as that context's content.text.
Create a new context when the next start-number/range label appears.

Return this schema:
{
  "contexts": [
    {
      "id": "p4_71_73",
      "part": 4,
      "context_type": "AUDIO_SRT",
      "content": {"text": "Full talk transcript for questions 71-73."},
      "index": 0,
      "additional_meta": {"audio_start": 0.0, "audio_end": 0.0, "note": "REQUIRED. Vietnamese translation of the transcript. not translate summary transcript."},
      "questions": [
        {
          "question_number": 71,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Printed Part 4 question stem.",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correct_answer": "",
          "additional_meta": {"note": "REQUIRED. Vietnamese translation of the question stem, Vietnamese translation of options A-D, blank line, then Vietnamese explanation using talk keywords."}
        },
        {
          "question_number": 72,
          "question_type": "MULTIPLE_CHOICE",
          "content": "Printed Part 4 question stem.",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correct_answer": "",
          "additional_meta": {"note": "REQUIRED. Vietnamese translation of the question stem, Vietnamese translation of options A-D, blank line, then Vietnamese explanation using talk keywords."}
        }
      ]
    }
  ]
}

STRICT PART 4 RULES:
1. Every context part must be 4.
2. Every context_type must be AUDIO_SRT.
3. MUST take all questions from 71 to 100.
4. Questions sharing one talk must be nested in the same context's questions array.
5. Extract only Part 4 talk questions.
6. Preserve printed question numbers when visible.
7. Use transcript start-number/range labels to group questions; do not split questions from one label into separate contexts.
8. If a label says 71-73, only questions 71, 72, and 73 may reference that context.
9. The top-level JSON object must contain exactly one "contexts" array; do not add a top-level "questions" array.
10. Do not return nested groups, markdown tables, CSV, or any schema other than the JSON object above.
11. Never leave contexts.additional_meta.note or questions.additional_meta.note empty.
''';

  static const _reading = r'''
Analyze the attached exam image and extract all content into a raw JSON object.
OUTPUT CONSTRAINT: Output ONLY the raw JSON. No markdown, no ```json code fences, no explanations.
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)

{
    "contexts": [
        {
            "id": "Unique string ID (e.g., 'ctx_1', 'ctx_102')",
            "part": 6, // Integer (TOEIC part 1-7 or IELTS section). Store ONLY in context, NEVER in questions.
            "context_type": "READING_PASSAGE | IMAGE_DIAGRAM | STANDALONE",
            "content": {
                // READING_PASSAGE: Full text, replace blanks/indicators with placeholders like [[131]], [[132]]
                // IMAGE_DIAGRAM: Concise description of the chart/map/table
                // STANDALONE: Must be exactly {"text": ""}
                "text": "string"
            },
            "index": 0, // 0-based order of appearance in the image
            "additional_meta": { 
                "audio_start": 0.0, 
                "audio_end": 0.0, 
                "note": "REQUIRED. Provide the exact full translation of 'content.text' into Vietnamese (vn). If STANDALONE, leave as empty string." 
            },
            "questions": [
                {
                    "question_number": 131, // Printed question number as integer
                    "question_type": "MULTIPLE_CHOICE | FILL_IN_THE_BLANK | ESSAY | RECORDING",
                    "content": "Exact stem. For reading blanks with no separate stem, use '-------'.",
                    "options": ["Flat string array. Stripped of prefixes like (A), B., C), etc. Keep original order."],
                    "correct_answer": "Required choice label ('A', 'B', etc.). Solve if unmarked. 'UNKNOWN' as last resort.",
                    "additional_meta": {
                        "note": "REQUIRED. Strictly format this field exactly as follows:\n[Translation of option 1 into Vietnamese (vn)]\n[Translation of option 2 into Vietnamese (vn)]\n[Translation of option 3 into Vietnamese (vn)]\n[Translation of option 4 into Vietnamese (vn)]\n\n[Detailed grammatical/contextual explanation in Vietnamese (vn) explaining why the correct_answer is right.]"
                    }
                }
            ]
        }
    ]
}

STRICT ARCHITECTURE RULES:
1. Preferred response shape is contexts[] with each context containing its own questions[] array.
2. STANDALONE Questions: Every standalone question (e.g., TOEIC Part 5) MUST have its own unique, dedicated context entry (context_type: "STANDALONE", content: {"text": ""}). NEVER group multiple standalone questions into a single context.
3. SHARED Contexts: Questions sharing a passage or diagram must reference the exact same shared context ID.
4. Extract every visible question. Never leave correct_answer or additional_meta.note empty.
5. In 'questions.additional_meta.note', ensure there is a clear new line separating the option translations and the final explanation.
''';

  static const noteContract = r'''VIETNAMESE NOTE CONTRACT:
TRANSLATION TARGET LANGUAGE: Vietnamese (vn)
1. Every contexts[].additional_meta.note and questions[].additional_meta.note value must be natural Vietnamese text, never English-only placeholder text.
2. For STANDALONE contexts, contexts[].additional_meta.note must be an empty string.
3. For AUDIO_SRT, READING_PASSAGE, and IMAGE_DIAGRAM contexts, contexts[].additional_meta.note must contain the Vietnamese translation or Vietnamese summary of contexts[].content.text.
4. Every question note is REQUIRED and must be non-empty. Do not use "if available", "leave empty", or similar conditional wording.
5. Format questions[].additional_meta.note exactly like this, with one translated line per source line and one blank line before the explanation:
[Vietnamese translation of the question stem, unless the stem is exactly "-------"]
[Vietnamese translation of option A]
[Vietnamese translation of option B]
[Vietnamese translation of option C]
[Vietnamese translation of option D, if present]

[Detailed Vietnamese grammar/context explanation explaining why correct_answer is right, using transcript/passage keywords.]
6. If correct_answer is empty because no answer key is visible, still provide Vietnamese translations and explain what evidence is visible; do not leave the note empty.''';
}
