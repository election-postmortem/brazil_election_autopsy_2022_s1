#!/bin/bash

./tools/md2pdf.sh README.md README.pdf

./tools/md2pdf.sh analysis/README.md analysis/README.pdf

./tools/md2pdf.sh analysis/sp/ANALYSIS-SP.md analysis/sp/ANALYSIS-SP.pdf

./tools/html2pdf.sh analysis/sp/ANALYSIS-SP-pt_br.html

./tools/md2pdf.sh tse_public_data/README.md tse_public_data/README.pdf

./tools/md2pdf.sh bu_statistics/README.md bu_statistics/README.pdf
