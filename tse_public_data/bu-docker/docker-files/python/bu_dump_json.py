##
## This is a `bu_dump.py` version that writes JSON files.
##
## You can easily compare the changes using:
##   `diff bu_dump.py bu_dump_json.py`
##

import argparse
import logging
import os
import sys
import os.path

import asn1tools


def espacos(profundidade: int):
    return "  " * profundidade


def valor_membro(membro):
    if isinstance(membro, (bytes, bytearray)):
        return "\"" + bytes(membro).hex() + "\""
    elif isinstance(membro, (int, float)):
        return membro
    else:
        return f"\"{membro}\""


def write_list(fout, lista: list, profundidade: int):
    indent = espacos(profundidade)
    lng = len(lista)
    for i, membro in enumerate(lista):
        if type(membro) is dict:
            fout.write(f"{indent}{{\n")
            write_dict(fout, membro, profundidade + 1)
            if i < lng-1:
                fout.write(f"{indent}}},\n")
            else:
                fout.write(f"{indent}}}\n")
        else:
            write_entry(fout, f"{indent}{valor_membro(membro)}", i, lng)


def write_dict(fout, entidade: dict, profundidade: int):
    indent = espacos(profundidade)
    lng = len(entidade)
    for i, key in enumerate(sorted(entidade)):
        membro = entidade[key]
        if type(membro) is dict:
            fout.write(f"{indent}\"{key}\": {{\n")
            write_dict(fout, membro, profundidade + 1)
            if i < lng-1:
                fout.write(f"{indent}}},\n")
            else:
                fout.write(f"{indent}}}\n")
        elif type(membro) is list:
            fout.write(f"{indent}\"{key}\": [\n")
            write_list(fout, membro, profundidade + 1)
            if i < lng-1:
                fout.write(f"{indent}],\n")
            else:
                fout.write(f"{indent}]\n")
        elif type(membro) is tuple:
            fout.write(f"{indent}\"{key}\": [\n")
            write_list(fout, list(membro) , profundidade + 1)
            if i < lng-1:
                fout.write(f"{indent}],\n")
            else:
                fout.write(f"{indent}]\n")
        else:
            write_entry(fout, f"{indent}\"{key}\": {valor_membro(membro)}", i, lng)



def write_entry(fout, e, i: int, lng: int):
    if i == lng-1:
        fout.write(e+"\n")
    else:
        fout.write(e+",\n")


def processa_bu(asn1_paths: list, bu_path: str):
    conv = asn1tools.compile_files(asn1_paths, codec="ber")
    if os.path.isdir(bu_path):
        print(f"** Directory: {bu_path}")
        files = os.listdir(bu_path)
        for f in files:
            if f.endswith('.bu'):
                file = f"{bu_path}/{f}"
                dump_bu(conv, file)
    elif os.path.isfile(bu_path):
        dump_bu(conv, bu_path)
    else:
        print(f"** Special file: {bu_path}" )


def dump_bu(conv, bu_path: str):
    bu_path_json = f"{bu_path}.json"
    if os.path.exists(bu_path_json) or os.path.exists(f"{bu_path_json}.gz"):
        print(f"-- Skipping: {bu_path}")
        return
    with open(bu_path, "rb") as file:
        envelope_encoded = bytearray(file.read())
    envelope_decoded = conv.decode("EntidadeEnvelopeGenerico", envelope_encoded)
    bu_encoded = envelope_decoded["conteudo"]
    del envelope_decoded["conteudo"]  # remove o conteúdo para não imprimir como array de bytes
    print(f"-- Writing JSON to: {bu_path_json}")
    fout = open(bu_path_json, "w")
    fout.write("{\n")
    fout.write("  \"EntidadeEnvelopeGenerico\": {\n")
    write_dict(fout, envelope_decoded, 2)
    fout.write("  },\n")
    bu_decoded = conv.decode("EntidadeBoletimUrna", bu_encoded)
    fout.write("  \"EntidadeBoletimUrna\": {\n")
    write_dict(fout, bu_decoded, 2)
    fout.write("  }\n")
    fout.write("}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Converte um Boletim de Urna (BU) da Urna Eletrônica (UE) e imprime um extrato",
        formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("-a", "--asn1", nargs="+", required=True,
                        help="Caminho para o arquivo de especificação asn1 do BU")
    parser.add_argument("-b", "--bu", type=str, required=True,
                        help="Caminho para o arquivo de BU originado na UE")
    parser.add_argument("--debug", action="store_true", help="ativa o modo DEBUG do log")

    args = parser.parse_args()

    bu_path = args.bu
    asn1_paths = args.asn1
    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=level, format="%(asctime)s - %(levelname)s - %(message)s")

    logging.info("Converte %s com as especificações %s", bu_path, asn1_paths)
    if not os.path.exists(bu_path):
        logging.error("Arquivo do BU (%s) não encontrado", bu_path)
        sys.exit(-1)
    for asn1_path in asn1_paths:
        if not os.path.exists(asn1_path):
            logging.error("Arquivo de especificação do BU (%s) não encontrado", asn1_path)
            sys.exit(-1)

    processa_bu(asn1_paths, bu_path)


if __name__ == "__main__":
    main()
