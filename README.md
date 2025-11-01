# 📚 KOReader Custom Patches

Este repositório contém **patches modificados** para o [KOReader](https://github.com/koreader/koreader) que adaptei e testei de acordo com minhas necessidades pessoais de uso.

> **Aviso:** Nenhum destes patches foi criado inteiramente por mim. Todos foram **baseados em trabalhos de outros desenvolvedores**, aos quais dou o devido crédito.

---

## Objetivo

Essas modificações têm como objetivo:

- Personalizar o comportamento e a aparência de certos recursos do KOReader;
- Corrigir pequenos bugs encontrados nas versões originais dos patches;
- Adaptar o funcionamento para uso em dispositivos específicos;
- Integrar ideias de diferentes versões compartilhadas por outros usuários.

---

## Patches incluídos

| Arquivo | Descrição | Base / Crédito |
|----------|------------|----------------|
| `2-reader-header-footer.lua` | Exibe cabeçalho e rodapé configuráveis com informações do livro, status e progresso de leitura. | Baseado no patch original de [Joshua Cant](https://github.com/joshuacant/KOReader.patches) e nas alterações compartilhadas por [Isaac_729](https://www.reddit.com/user/Isaac_729/). |
| `2-sleep-overlay.lua` | Aplica uma imagem de sobreposição aleatória à tela de descanso, permitindo ajustar o modo de redimensionamento das imagens. | Baseado no patch original de [omer-faruq](https://github.com/omer-faruq/koreader-user-patches.git) |

---

## Como aplicar (pode variar de acordo com o patch)

1. Baixe ou clone este repositório:

   ```bash
   git clone https://github.com/Djeymisson/KOReader.patches.git
   ```

2. Copie os arquivos `.lua` desejados para a pasta `patches/` do seu KOReader.
3. Reinicie o KOReader ou use o comando interno de recarregamento de patches (quando disponível).

---

## Licença

Os arquivos aqui seguem as licenças originais dos patches dos quais derivam.  
Modificações pessoais são compartilhadas sob a mesma licença para manter a compatibilidade (ex.: **GPLv3**).

> *Este é um repositório pessoal de testes e adaptações. Use por sua conta e risco.*
