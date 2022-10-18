# BU Analysis

This directory contains statistical analysis of the BU files of the 
Brazilian election (2022/10/02), separated by state (UF) in Brazil.

- `BU` stands for "Boletin de Urna" (Ballot Box).
- `UF` stands for a state in Brazil.

All the analysis are based on **public available data** of the Voting Machines
of the election in Brazil from the TSE website : http://resultados.tse.jus.br

- TSE stands for: "Tribunal Superior Eleitoral" ("Superior Electoral Court").

## `./sp` (São Paulo)

- `./sp/bu-statistics--sp--$METRIC.csv`: a CSV file for each analyzed metric.
- `./sp/bus.csv`: A CSV file with information of all the BUs used in the analysis.
  - *This file allows you to check the data with the TSE website and the results of the analysis.* 
- `./sp/ANALYSIS-SP.md`: the description of the insights and anomalies found.
  - `./sp/ANALYSIS-SP.html`: HTML version.
  - `./sp/ANALYSIS-SP.pdf`: PDF version.
  - `./sp/ANALYSIS-SP-pt_br.html`: HTML version (automatic translation: *en* to *pt_BR*).
  - `./sp/ANALYSIS-SP-pt_br.pdf`: PDF version (automatic translation: *en* to *pt_BR*).

- NOTE: The state of São Paulo represents 27 million of votes
  from the 123 million of votes in Brazil

## `./mg` (Minas Gerais)

- `./mg/bu-statistics--mg--$METRIC.csv`: a CSV file for each analyzed metric.

## `./ba` (Bahia)

- `./ba/bu-statistics--ba--$METRIC.csv`: a CSV file for each analyzed metric.

## `./rj` (Rio de Janeiro)

- `./rj/bu-statistics--rj--$METRIC.csv`: a CSV file for each analyzed metric.

## See Also

See the other directories in the project:

- `../tse_public_data/`
- `../bu_statistics/`

## LICENSE

MIT License

## Authors

The authors of this analysis worked hard to give a fully reproducible work,
what legitimates the data and the analysis of this Election data.

This work was verified by people at different major universities in
Brazil, USA and Switzerland.

If necessary this address will be used to guarantee the authorship of the work:

```text
1Gh5Qtc7UpLt31Ma85HwZLduGwPFHFS2AH
```
