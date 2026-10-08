# Workflow n8n — Générateur de réponses TCF Canada

## Informations

- **Workflow ID** : `A3zcF2onGYWKyH0Z`
- **Version** : v2 — Sortie HTML colorée
- **Projet** : dev tcf (`devtcf77@gmail.com`)
- **URL Webhook** : `POST http://localhost:5678/webhook/tcf-generator`
- **Credential** : Opencode Go (type `openAiApi`)
- **Modèle** : GPT-4o

## Types de tâches

| Code | Description |
|------|-------------|
| `ee-01` | Expression Écrite — Tâche 1 : Courriel (60-120 mots) |
| `ee-02` | Expression Écrite — Tâche 2 : Blog (120-150 mots) |
| `ee-03` | Expression Écrite — Tâche 3 : Synthèse de documents |
| `eo-02` | Expression Orale — Tâche 2 : Dialogue (10 questions min.) |
| `eo-03` | Expression Orale — Tâche 3 : Argumentation (3 paragraphes) |

## Payload webhook

```json
{
  "contenu": "le sujet ou la consigne à traiter",
  "type": "ee-01"
}
```

## Réponse JSON

La réponse contient le HTML dans `modele_reponse`, wrappé dans un `<div style="color: rgb(45, 194, 107);">` :

```json
{
  "type": "ee-01",
  "sujet": "copié du payload",
  "modele_reponse": "<div style=\"color: rgb(45, 194, 107); font-family: Arial, sans-serif; line-height: 1.6;\"><h1>Titre</h1><p>Contenu HTML...</p></div>"
}
```

Le contenu HTML est généré sans balises `<html>` ni `<body>`, prêt à être injecté dans une page.

## Architecture

```
Webhook (POST) → Construire le Prompt → Agent IA (GPT-4o) → Répondre au Webhook
```

## Détail des nodes

### 1. Webhook (`n8n-nodes-base.webhook` v2.1)

- Path : `tcf-generator`
- Méthode : POST
- responseMode : `responseNode`

### 2. Construire le Prompt (`n8n-nodes-base.set` v3.4)

Deux champs générés :

- **systemPrompt** — Contient la méthodologie complète TCF (EE + EO) extraite de reussir-tcf.com
- **userInput** — Composé du sujet + type + consignes de génération

### 3. OpenAI Model (`@n8n/n8n-nodes-langchain.lmChatOpenAi` v1.3)

- Modèle : `gpt-4o`
- Temperature : 0.7
- Max tokens : 2000
- Credential : Opencode Go

### 4. Agent IA (`@n8n/n8n-nodes-langchain.agent` v3.1)

- promptType : `define`
- Texte : `$json.userInput`
- System message : `$json.systemPrompt` du node "Construire le Prompt"

### 5. Répondre (`n8n-nodes-base.respondToWebhook` v1.5)

- respondWith : `json`
- Retourne { type, sujet, modele_reponse }

## Méthodologie intégrée dans le prompt system

### Expression Écrite

**Tâche 1 — Courriel (60-120 mots)**

Structure :
1. Adresse : De (expéditeur) / A (destinataire)
2. Objet
3. Appellatif + Salutation
4. Motif du courriel
5. Contenu du courriel
6. Formule finale
7. Signature (prénom, à gauche)

Types possibles : narratif, descriptif, informatif, explicatif

**Tâche 2 — Blog (120-150 mots)**

Structure :
1. Objet/thème captivant et accrocheur
2. Salutation et appellatif
3. Motif du blog
4. Contenu du blog
5. Avis personnel + sensibilisation (conditionnel)
6. Formule finale
7. Signature (prénom, au milieu ou à gauche)

**Tâche 3 — Synthèse des documents**

Deux parties :
- Partie 1 (40-60 mots) : Présenter reformulée les documents (thème général + idées + arguments)
- Partie 2 (80-120 mots) : Argumentation personnelle (POUR / CONTRE / ARGUMENT-SOLUTION)

### Expression Orale

**Tâche 1 — La Présentation (2 min, sans préparation)**

Candidat se présente : état civil, cursus, ville, hobbies, projets

**Tâche 2 — Le Dialogue (5min30s, 2min prépa)**

- Dialogue avec l'examinateur (10 questions min, hiérarchisées)
- Formel (vouvoiement) ou informel (tutoiement)
- Critères : initiation, gestion du blanc, prise de congé

**Tâche 3 — L'Argumentation (4min30s, sans préparation)**

- 3 paragraphes : Arg + Explication + Exemple / Résumé + Solutions
- Stratégies : POUR ou CONTRE

## Code SDK n8n (pour recréer/modifier)

```javascript
import { workflow, node, trigger, newCredential, languageModel, expr } from '@n8n/workflow-sdk';

const webhookTrigger = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Webhook',
    position: [240, 300],
    parameters: {
      httpMethod: 'POST',
      path: 'tcf-generator',
      responseMode: 'responseNode',
      options: {}
    },
    output: [{ body: { contenu: 'string', type: 'string' } }]
  }
});

const buildPrompt = node({
  type: 'n8n-nodes-base.set',
  version: 3.4,
  config: {
    name: 'Construire le Prompt',
    position: [540, 300],
    parameters: {
      mode: 'manual',
      assignments: {
        assignments: [
          {
            id: 'system-prompt',
            name: 'systemPrompt',
            type: 'string',
            value: expr(`"Tu es un expert en préparation au TCF Canada, spécialisé en expression écrite et orale. Tu connais parfaitement les méthodologies de chaque tâche du TCF. Tu génères des modèles de réponse conformes aux critères d'évaluation du TCF Canada, servant d'exemples de correction pour les étudiants.\\n\\n=== MÉTHODOLOGIE EXPRESSION ÉCRITE ===\\n\\n**Tâche 1 : Le courriel (60-120 mots)**\\nStructure :\\n- Adresse : De (expéditeur) / A (destinataire)\\n- Objet\\n- Appellatif + Salutation\\n- Motif du courriel\\n- Contenu du courriel\\n- Formule finale\\n- Signature (prénom, à gauche)\\nTypes possibles : narratif, descriptif, informatif, explicatif\\n\\n**Tâche 2 : Le Blog (120-150 mots)**\\nStructure :\\n1) Objet/thème captivant et accrocheur\\n2) Salutation et appellatif\\n3) Motif du blog\\n4) Contenu du blog\\n5) Avis personnel + sensibilisation (utiliser le conditionnel)\\n6) Formule finale\\n7) Signature (prénom, au milieu ou à gauche)\\n\\n**Tâche 3 : La synthèse des documents**\\nDeux parties :\\n- Partie 1 (40-60 mots) : Présenter reformulée les documents\\n  - Thème général + idées générales + arguments distinctifs\\n- Partie 2 (80-120 mots) : Argumentation personnelle\\n  - 3 stratégies au choix : POUR, CONTRE, ou ARGUMENT-SOLUTION\\n  - 2 arguments pour la thèse + 1 argument pour les limites\\n\\n=== MÉTHODOLOGIE EXPRESSION ORALE ===\\n\\n**Tâche 1 : La Présentation (2 min, sans préparation)**\\nCandidat se présente:\\n- État civil (prénom, nom, âge, département, situation matrimoniale, langues)\\n- Cursus scolaire et académique\\n- Ville d'habitation actuelle\\n- Hobbies\\n- Projets d'avenir\\n\\n**Tâche 2 : Le Dialogue (5min30s, 2min de préparation)**\\n- Dialogue avec l'examinateur sur une thématique\\n- Le candidat est le fil conducteur\\n- Poser 10 questions minimum, hiérarchisées\\n- Peut être formel (vouvoiement) ou informel (tutoiement)\\n\\n3 critères:\\n1) Initiation : salutation + appellatif + bref condensé\\n2) Gestion du blanc : d'accord, super, ça marche...\\n3) Prise de congé : remerciement final\\n\\n**Tâche 3 : L'Argumentation (4min30s, sans préparation)**\\n- Sujet culturel, 3 paragraphes:\\n  - P1: Connecteur logique + Arg1 + Explication1 + Exemple1\\n  - P2: Connecteur logique + Arg2 + Explication2 + Exemple2\\n  - P3: Connecteur + résumé + SOLUTIONS\\n\\n2 stratégies:\\n- POUR (défendre le point de vue)\\n- CONTRE (rejeter le point de vue)\\n- 3ème paragraphe : résumé + solutions"`)
          },
          {
            id: 'user-input',
            name: 'userInput',
            type: 'string',
            value: expr(`"Voici le sujet:\\n\\n{{ $('Webhook').item.json.body?.contenu ?? $('Webhook').item.json.contenu }}\\n\\n\\nType de tâche: {{ $('Webhook').item.json.body?.type ?? $('Webhook').item.json.type }}\\n\\n\\nGénère un modèle de réponse complet et détaillé pour ce sujet, en suivant strictement la méthodologie correspondante au type indiqué. Le modèle doit:\\n- Respecter le nombre de mots imposé pour ce type de tâche\\n- Suivre la structure méthodologique exacte\\n- Inclure des connecteurs logiques appropriés\\n- Être suffisamment détaillé pour servir d'exemple de correction\\n- Être en bon français et sans fautes"`)
          }
        ]
      }
    },
    output: [{ systemPrompt: 'string', userInput: 'string' }]
  }
});

const openAiModel = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatOpenAi',
  version: 1.3,
  config: {
    name: 'OpenAI Model',
    position: [540, 500],
    parameters: {
      model: { __rl: true, mode: 'id', value: 'gpt-4o' },
      options: { temperature: 0.7, maxTokens: 2000 }
    },
    credentials: { openAiApi: newCredential('Opencode Go') }
  }
});

const aiAgent = node({
  type: '@n8n/n8n-nodes-langchain.agent',
  version: 3.1,
  config: {
    name: 'Générateur TCF',
    position: [840, 300],
    parameters: {
      promptType: 'define',
      text: expr('{{ $json.userInput }}'),
      options: { systemMessage: expr('{{ $("Construire le Prompt").item.json.systemPrompt }}') }
    },
    subnodes: { model: openAiModel }
  }
});

const respondToWebhook = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Répondre',
    position: [1140, 300],
    parameters: {
      respondWith: 'json',
      responseBody: expr(`{{ JSON.stringify({ type: $('Webhook').item.json.body?.type ?? $('Webhook').item.json.type, sujet: $('Webhook').item.json.body?.contenu ?? $('Webhook').item.json.contenu, modele_reponse: $json.output }) }}`)
    }
  }
});

export default workflow('tcf-generator', 'Générateur de réponses TCF Canada')
  .add(webhookTrigger)
  .to(buildPrompt)
  .to(aiAgent)
  .to(respondToWebhook);
```

## Exemple d'appel curl

```bash
curl -X POST http://localhost:5678/webhook/tcf-generator \
  -H "Content-Type: application/json" \
  -d '{
    "contenu": "Vous envoyez un courriel à votre médecin pour annuler votre prochain rendez-vous. Vous lui donnez la raison et vous présentez vos excuses.",
    "type": "ee-01"
  }'
```
