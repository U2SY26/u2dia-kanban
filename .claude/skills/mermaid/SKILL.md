---
name: mermaid
description: "Mermaid 다이어그램 생성"
---

# Mermaid — 다이어그램 생성

## 사용 시기
- "다이어그램", "flowchart", "시퀀스 다이어그램", "ERD", "클래스 다이어그램" 요청 시

## 지원 다이어그램

| 타입 | 키워드 | 용도 |
|------|--------|------|
| flowchart | `flowchart TD` | 프로세스, 워크플로우 |
| sequence | `sequenceDiagram` | API 흐름, 상호작용 |
| classDiagram | `classDiagram` | 객체 구조, 관계 |
| erDiagram | `erDiagram` | DB 스키마, 엔티티 관계 |
| gantt | `gantt` | 일정, 타임라인 |
| stateDiagram | `stateDiagram-v2` | 상태 전이 |
| pie | `pie` | 비율, 분포 |
| mindmap | `mindmap` | 브레인스토밍, 구조화 |

## 원칙

1. 가독성 우선 — 노드 10개 이내 권장, 복잡하면 분할
2. 방향은 TD(위→아래) 기본, 필요시 LR(좌→우)
3. 한국어/영어 모두 지원, 프로젝트 언어에 맞춤
4. ```mermaid 코드블록으로 출력
