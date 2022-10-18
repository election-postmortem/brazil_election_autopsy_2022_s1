# Brazil Election Autopsy - *Season 1 (2022/10/02)*

The main objective of this project is to facilitate public access to the data
of the Brazilian election that took place in `2022/Oct/02`.

It's separated in 3 subprojects.

## `tse_public_data/`

Guidance on obtaining and exporting the **public available data** of the Voting Machines of the election
in Brazil from the TSE website.

- TSE stands for: "Tribunal Superior Eleitoral" ("Superior Electoral Court").

## `bu_statistics/`

A Dart program that analises and generates statistics from the extracted information
from the Voting Machine files (".bu" files).

- `BU` stands for "Boletin de Urna" (Ballot Box).

## `analysis/`

Directory with statistical analysis of the BU files of the
Brazilian election, separated by state (UF) in Brazil.

- `UF` stands for a state in Brazil.

## `tools/`

Scripts to generate HTML and PDF documents.

## NOTES

This project provides all the tools and information to be fully
reproduced. This project was built so that anyone can fully reproduce the
analysis from scratch using the original data provided by the TSE website.

**It's very important to have multiple different analysis of this data.**

This is the first time that an election data (through electronic Voting Machines) 
is public available with this level of detail and for an entire country.

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
