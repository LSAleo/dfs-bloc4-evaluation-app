<?php

declare(strict_types=1);

/*
 * generate-code-reference.php — Genere une reference de classes en Markdown
 * a partir du CODE SOURCE APPLICATIF, hors dependances tierces.
 *
 *   php tools/generate-code-reference.php
 *
 * Sortie : livrables/05_documentation_maintenance/documentation_technique/reference_classes.md
 *
 * L'analyse s'appuie sur le tokenizer de PHP (token_get_all) et non sur la
 * reflexion : le generateur n'a donc pas besoin que `vendor/` soit installe ni
 * que l'application demarre, ce qui le rend rejouable sur n'importe quelle
 * machine et dans le pipeline CI.
 *
 * Perimetre volontairement limite aux repertoires du code metier ; `vendor/` et
 * `node_modules/` sont exclus, conformement a l'attendu du livrable.
 */

const SCAN_DIRS = ['app', 'database/seeders', 'database/factories'];
const OUTPUT = 'livrables/05_documentation_maintenance/documentation_technique/reference_classes.md';

$root = dirname(__DIR__);
chdir($root);

/** Liste recursivement les fichiers .php d'un repertoire. */
function php_files(string $dir): array
{
    if (! is_dir($dir)) {
        return [];
    }

    $files = [];
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS));

    foreach ($it as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $files[] = str_replace('\\', '/', $file->getPathname());
        }
    }

    sort($files);

    return $files;
}

/** Nettoie un docblock pour n'en garder que le texte de description. */
function clean_doc(string $doc): string
{
    $lines = [];

    foreach (preg_split('/\R/', $doc) as $line) {
        $line = trim(preg_replace('#^\s*(/\*\*|\*/|\*)#', '', $line) ?? '');

        if ($line === '' || str_starts_with($line, '@')) {
            continue;
        }

        $lines[] = $line;
    }

    return trim(implode(' ', $lines));
}

/**
 * Extrait d'un fichier : namespace, classes/interfaces/traits/enums avec leur
 * docblock, et leurs methodes publiques avec signature et docblock.
 */
function parse_file(string $path): array
{
    $tokens = token_get_all((string) file_get_contents($path));
    $count = count($tokens);

    $namespace = '';
    $structures = [];
    $pendingDoc = '';
    $modifiers = [];
    // Les fichiers du projet declarent une structure par fichier : toute methode
    // rencontree apres une declaration de classe lui est rattachee, jusqu'a la
    // declaration suivante. C'est plus robuste qu'un comptage d'accolades, que
    // les closures et les structures imbriquees faussent facilement.
    $currentIdx = null;

    for ($i = 0; $i < $count; $i++) {
        $token = $tokens[$i];

        if (is_string($token)) {
            continue;
        }

        [$id, $text] = $token;

        if ($id === T_DOC_COMMENT) {
            $pendingDoc = clean_doc($text);
            continue;
        }

        if (in_array($id, [T_WHITESPACE, T_COMMENT], true)) {
            continue;
        }

        if ($id === T_NAMESPACE) {
            $parts = [];

            for ($j = $i + 1; $j < $count; $j++) {
                if (is_string($tokens[$j])) {
                    break;
                }
                if (in_array($tokens[$j][0], [T_STRING, T_NAME_QUALIFIED], true)) {
                    $parts[] = $tokens[$j][1];
                }
            }

            $namespace = implode('', $parts);
            $pendingDoc = '';
            continue;
        }

        if (in_array($id, [T_ABSTRACT, T_FINAL, T_PUBLIC, T_PROTECTED, T_PRIVATE, T_STATIC, T_READONLY], true)) {
            $modifiers[] = strtolower($text);
            continue;
        }

        if (in_array($id, [T_CLASS, T_INTERFACE, T_TRAIT, T_ENUM], true)) {
            // Ignore les classes anonymes (`new class {...}`).
            $name = null;

            for ($j = $i + 1; $j < $count; $j++) {
                if (is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) {
                    continue;
                }
                if (is_array($tokens[$j]) && $tokens[$j][0] === T_STRING) {
                    $name = $tokens[$j][1];
                }
                break;
            }

            if ($name !== null) {
                // Stocke un index et non une reference : `$structures[] = &$current`
                // suivi de `$current = null` viderait l'element du tableau.
                $structures[] = [
                    'kind' => strtolower($text),
                    'name' => $name,
                    'fqcn' => $namespace !== '' ? $namespace.'\\'.$name : $name,
                    'doc' => $pendingDoc,
                    'abstract' => in_array('abstract', $modifiers, true),
                    'methods' => [],
                    'file' => $path,
                ];
                $currentIdx = count($structures) - 1;
            }

            $pendingDoc = '';
            $modifiers = [];
            continue;
        }

        if ($id === T_FUNCTION && $currentIdx !== null) {
            $isPublic = ! in_array('private', $modifiers, true) && ! in_array('protected', $modifiers, true);

            // Reconstitue le nom et la signature jusqu'a l'accolade ou au `;`.
            $signature = '';
            $name = '';
            $seenName = false;

            for ($j = $i + 1; $j < $count; $j++) {
                $t = $tokens[$j];

                if (is_string($t)) {
                    if ($t === '{' || $t === ';') {
                        break;
                    }
                    $signature .= $t;
                    continue;
                }

                if (! $seenName && $t[0] === T_STRING) {
                    $name = $t[1];
                    $seenName = true;
                    $signature .= $t[1];
                    continue;
                }

                $signature .= $t[0] === T_WHITESPACE ? ' ' : $t[1];
            }

            // On exclut seulement le constructeur et le destructeur : les autres
            // methodes magiques font partie de l'API publique — `__invoke()` est
            // par exemple le point d'entree du DashboardController.
            $excluded = ['__construct', '__destruct'];

            if ($isPublic && $name !== '' && ! in_array($name, $excluded, true)) {
                $structures[$currentIdx]['methods'][] = [
                    'name' => $name,
                    'signature' => trim(preg_replace('/\s+/', ' ', $signature) ?? ''),
                    'doc' => $pendingDoc,
                    'static' => in_array('static', $modifiers, true),
                ];
            }

            $pendingDoc = '';
            $modifiers = [];
            continue;
        }

        $pendingDoc = '';
        $modifiers = [];
    }

    return $structures;
}

$all = [];
$fileCount = 0;

foreach (SCAN_DIRS as $dir) {
    foreach (php_files($dir) as $file) {
        $fileCount++;

        foreach (parse_file($file) as $structure) {
            $all[] = $structure;
        }
    }
}

usort($all, static fn (array $a, array $b): int => strcmp($a['fqcn'], $b['fqcn']));

// Regroupe par namespace pour une lecture par couche applicative.
$byNamespace = [];

foreach ($all as $structure) {
    $ns = substr($structure['fqcn'], 0, strrpos($structure['fqcn'], '\\') ?: 0) ?: '(global)';
    $byNamespace[$ns][] = $structure;
}

ksort($byNamespace);

$methodCount = array_sum(array_map(static fn (array $s): int => count($s['methods']), $all));

$out = [];
$out[] = '# Reference des classes — OpsTrack Field Service';
$out[] = '';
$out[] = '> **Fichier genere. Ne pas editer a la main.**';
$out[] = '> Produit par [`tools/generate-code-reference.php`](../../../tools/generate-code-reference.php)';
$out[] = '> a partir du code source applicatif (`'.implode('`, `', SCAN_DIRS).'`), **hors dependances tierces**';
$out[] = '> (`vendor/`, `node_modules/`). Regeneration : `php tools/generate-code-reference.php`.';
$out[] = '';
$out[] = sprintf(
    'Perimetre analyse : **%d fichiers PHP**, **%d classes/interfaces/traits/enums**, **%d methodes publiques**.',
    $fileCount,
    count($all),
    $methodCount
);
$out[] = '';
$out[] = '## Sommaire';
$out[] = '';

foreach ($byNamespace as $ns => $structures) {
    $out[] = sprintf('- `%s` — %d element(s)', $ns, count($structures));
}

$out[] = '';

foreach ($byNamespace as $ns => $structures) {
    $out[] = '---';
    $out[] = '';
    $out[] = '## `'.$ns.'`';
    $out[] = '';

    foreach ($structures as $s) {
        $out[] = sprintf('### %s `%s`%s', ucfirst($s['kind']), $s['name'], $s['abstract'] ? ' *(abstraite)*' : '');
        $out[] = '';
        $out[] = 'Source : `'.$s['file'].'`';
        $out[] = '';

        if ($s['doc'] !== '') {
            $out[] = $s['doc'];
            $out[] = '';
        }

        if ($s['methods'] === []) {
            $out[] = '*Aucune methode publique.*';
            $out[] = '';
            continue;
        }

        $out[] = '| Methode publique | Description |';
        $out[] = '| --- | --- |';

        foreach ($s['methods'] as $m) {
            $doc = $m['doc'] !== '' ? str_replace('|', '\\|', $m['doc']) : '—';
            $out[] = sprintf(
                '| `%s%s` | %s |',
                $m['static'] ? 'static ' : '',
                str_replace('|', '\\|', $m['signature']),
                $doc
            );
        }

        $out[] = '';
    }
}

@mkdir(dirname(OUTPUT), 0o755, true);
file_put_contents(OUTPUT, implode("\n", $out)."\n");

printf(
    "[ok] %s genere : %d fichiers, %d classes, %d methodes publiques\n",
    OUTPUT,
    $fileCount,
    count($all),
    $methodCount
);
