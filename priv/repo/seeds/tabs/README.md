# Tablaturas de seed

Cada arquivo `*.txt` deste diretório vira uma tablatura quando `priv/repo/seeds.exs` roda. Isso acontece a cada `docker compose up`. Uma tablatura cujo título já existe no banco é ignorada, então rodar de novo não duplica nada.

Os arquivos `*.txt` estão no `.gitignore`. Tablaturas de músicas protegidas por direitos autorais, como as transcrições do Ultimate Guitar, não devem ir para o repositório público. Mantenha-as só localmente.

## Formato

```
# Linhas com # e linhas em branco são ignoradas.
title: Nome da tablatura
E3 D0 G2 E3 B0 D0 G2 A0 D2 G2 A0 B0 D2 G2
A2 D4 e2 A2 B3 D4 G4 A0 B2 D4 e2 A0 B2 G2 D4
```

- Uma linha `title:` por arquivo.
- Cada outra linha é um compasso, com as notas na mesma notação da interface: letra da corda + casa. `E` é o Mi grave e `e` o Mi agudo.

Para recriar uma tablatura depois de editar o arquivo, exclua-a pela interface em `/tabs` e rode `mix run priv/repo/seeds.exs`.
