# Catálogo de acordes importado

Fonte: [tombatossals/chords-db](https://github.com/tombatossals/chords-db),
`lib/guitar.json` no commit
[`df06fa7b425cf5fd29485ff6591236b3557e3fac`](https://github.com/tombatossals/chords-db/tree/df06fa7b425cf5fd29485ff6591236b3557e3fac).
SHA-256 do JSON original: `cfe439962b2f444d2c341b1f0261403b4c3a3416e321147286fc608922699974`.
Licença: MIT, copyright © 2016 David Rubert. A licença integral está em
[`chords-db-LICENSE`](chords-db-LICENSE). O arquivo local
`priv/repo/chords_db_guitar.json` é derivado dessa fonte.

Para regenerar o catálogo, baixe o `lib/guitar.json` desse commit e rode
`python3 scripts/import_chords_db.py /caminho/guitar.json`. O script usa
apenas a biblioteca padrão do Python; o seed lê somente o arquivo gerado,
sem rede durante execução ou deploy.

O script considera apenas as qualidades `major`, `minor`, `7`, `sus2`,
`sus4`, `dim` e `aug`, mapeadas respectivamente para as sete qualidades de
`ChordShape`. Cada posição é convertida da ordem E–A–D–G–B–e da fonte
para a ordem interna e–B–G–D–A–E. `-1` vira `nil`; `0` mantém a corda
solta; as demais casas são absolutas: `baseFret + fret - 1`. As classes de
altura de todas as cordas soantes precisam ser **exatamente** as notas da
qualidade declarada, incluindo a fundamental. A corda-raiz escolhida é a
mais grave que toca essa fundamental.

Posições com corda solta usam `base_fret = 0`; posições fechadas usam como
base a menor casa tocada. Ambas ficam fixadas na posição fornecida pela
fonte (`min_base_fret = max_base_fret`); as fechadas recebem `movable = true`
para o diagrama mostrar corretamente a janela do braço. Outras
transposições exigiriam nova validação e não são criadas implicitamente.

Dos 338 registros nas sete qualidades, 10 foram rejeitados por notas
incompatíveis com o rótulo e 2 eram duplicatas internas. Restaram 326
posições distintas no arquivo curado. O seed compara seus padrões de
casas com todas as posições abertas e móveis dos 25 shapes originais.
Sessenta e cinco posições coincidem com esse catálogo; o seed preserva
seus slugs e adiciona as outras 261, chegando a **286 shapes** no banco.
O upsert usa slug como identidade.
Executar o seed novamente atualiza as mesmas linhas sem duplicá-las.

O motor lê o catálogo uma vez por análise. Cada posição importada tem
apenas um `base_fret` válido, de modo que aumenta o número de shapes
avaliados, mas não multiplica as transposições por shape. O teste de
catálogo verifica a contagem, a conversão, as qualidades e a ausência de
duplicatas; a suíte de análise cobre o comportamento do motor.
