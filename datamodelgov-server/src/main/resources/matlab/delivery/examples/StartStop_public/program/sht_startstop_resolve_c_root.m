function cRoot = sht_startstop_resolve_c_root(branchRoot)
%SHT_STARTSTOP_RESOLVE_C_ROOT Resolve the C project without a Chinese path literal.
%
% The independent StartupStop tree keeps the C project below its own root,
% while the main adaptive-model tree keeps the C project beside the M project
% under 05_program.  Search the current root and a few parents by file
% features, rather than embedding either Chinese directory name in an M file.
% This also avoids MATLAB R2019b code-page corruption of a literal path.

searchRoots = {};
probe = branchRoot;
for level = 0:3
    if isempty(probe)
        break;
    end
    searchRoots{end + 1} = probe; %#ok<AGROW>
    nextProbe = fileparts(probe);
    if strcmp(nextProbe, probe)
        break;
    end
    probe = nextProbe;
end

candidates = {};
for rootIndex = 1:numel(searchRoots)
    root = searchRoots{rootIndex};
    entries = dir(root);
    for k = 1:numel(entries)
        if ~entries(k).isdir || any(strcmp(entries(k).name, {'.', '..'}))
            continue;
        end
        folder = fullfile(root, entries(k).name);
        hasThreeModel = exist(fullfile(folder, 'Turboshaft-TS.mdl'), 'file') == 2;
        hasSixModel = exist(fullfile(folder, 'Turboshaft-TS-Split.mdl'), 'file') == 2;
        hasDll = exist(fullfile(folder, 'x64', 'Release', 'GTESS.dll'), 'file') == 2;
        if hasThreeModel && hasSixModel && hasDll
            candidates{end + 1} = folder; %#ok<AGROW>
        end
    end
end

% Remove duplicates when the same folder is reached from two search roots.
if ~isempty(candidates)
    candidates = unique(candidates, 'stable');
end
assert(numel(candidates) == 1, ...
    'Cannot uniquely locate the start-stop C project; candidate count=%d.', numel(candidates));
cRoot = candidates{1};
end
