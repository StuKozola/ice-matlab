function outputFile = build_toolbox(opts)
%BUILD_TOOLBOX Package ice-matlab as a .mltbx Add-On.
%   outputFile = build_toolbox()
%       builds dist/ice-matlab-<version>.mltbx from the working tree.
%
%   outputFile = build_toolbox(Version="0.2.0")
%       overrides the version string baked into the .mltbx metadata.
%
%   The output is a self-contained MATLAB Add-On installer that:
%     - Adds +ice and examples to the path on install.
%     - Excludes tests/, ice_developer_docs/, extracted_text/, data/,
%       .env, .git, *.stackdump, and other dev-time artefacts.
%     - Targets MATLAB R2024b or newer (the version this toolbox was
%       developed against).
%
%   Uses matlab.addons.toolbox.ToolboxOptions (R2023a+) so we don't have
%   to hand-author the .prj XML. Run from the toolbox root.

arguments
    opts.Version (1,1) string = "0.1.0"
    opts.OutputDir (1,1) string = "dist"
end

toolboxRoot = fileparts(mfilename("fullpath"));
oldDir = cd(toolboxRoot);
cleanupDir = onCleanup(@() cd(oldDir));

if ~isfolder(opts.OutputDir); mkdir(opts.OutputDir); end

% Choose the root for ToolboxOptions. Pointing at the current directory
% picks up every file then filters by ToolboxFiles / excluded patterns.
toolboxFolder = pwd;
identifier = "0c1e7e4a-ice-matlab-7d2f-46b1-9a3f-ice-matlab";  % stable GUID for upgrades

% Include the toolbox folder; ToolboxOptions will recurse and apply the
% file-exclusion patterns below.
toolboxOpts = matlab.addons.toolbox.ToolboxOptions(toolboxFolder, identifier);

toolboxOpts.ToolboxName = "ICE Market Data (ice-matlab)";
toolboxOpts.ToolboxVersion = char(opts.Version);
toolboxOpts.Description = sprintf([
    'MATLAB toolbox for ingesting ICE Data Services market data.\n\n', ...
    'Includes:\n', ...
    '  +ice.api  -  XML Quote / History / Options / FlexHistory clients\n', ...
    '  +ice.ftp  -  FTP transport, EOD readers (FTPCSD, FTPSEDOL)\n', ...
    '  +ice.sym  -  Symbol master (partitioned parquet)\n', ...
    '  +ice.jobs -  syncDailySymbology, backfillHistory (Task Scheduler entry points)\n', ...
    '  +ice.io   -  Optional DuckDB sink (requires R2026a+)\n\n', ...
    'See examples/ for runnable Live Scripts.']);
toolboxOpts.AuthorName = "Stuart Kozola";
toolboxOpts.AuthorEmail = "stuart.kozola@gradientboostedinvestments.com";
toolboxOpts.AuthorCompany = "Gradient Boosted Investments";

toolboxOpts.MinimumMatlabRelease = "R2024b";
% No upper bound; the partitioned-parquet path uses only stable APIs.

% Add +ice and examples to the path on install. (scheduled/ is .bat files
% so it doesn't need to be on the MATLAB path; users opt into Task
% Scheduler integration manually.)
toolboxOpts.ToolboxMatlabPath = [
    fullfile(toolboxFolder)                              % +ice resolves from here
    fullfile(toolboxFolder, "examples")
];

% Files NOT to ship. ToolboxOptions sets ToolboxFiles to "everything under
% the root"; we strip out tests, dev artefacts, and confidential docs.
excludePatterns = ["tests", "ice_developer_docs", "extracted_text", ...
    "data", ".env", ".git", ".github", ".vscode", ".idea", ".claude", ...
    ".gitignore", "*.stackdump", "build_toolbox.m", ...
    "ICE_MATLAB_Architecture_Plan.md", "extract_pdfs.py", "dist"];
keep = true(numel(toolboxOpts.ToolboxFiles), 1);
for k = 1:numel(toolboxOpts.ToolboxFiles)
    f = string(toolboxOpts.ToolboxFiles{k});
    rel = relativePath(f, toolboxFolder);
    if shouldExclude(rel, excludePatterns)
        keep(k) = false;
    end
end
toolboxOpts.ToolboxFiles = toolboxOpts.ToolboxFiles(keep);

outputFile = string(fullfile(opts.OutputDir, ...
    sprintf("ice-matlab-%s.mltbx", opts.Version)));
toolboxOpts.OutputFile = char(outputFile);

fprintf("Packaging %d files into %s...\n", numel(toolboxOpts.ToolboxFiles), outputFile);
matlab.addons.toolbox.packageToolbox(toolboxOpts);
fprintf("Done. Size: %.1f MB\n", dir(outputFile).bytes / 1e6);
end

function rel = relativePath(absPath, root)
% Best-effort cross-platform relpath for ToolboxOptions filtering.
absPath = string(absPath);
root = string(root);
if startsWith(absPath, root)
    rel = extractAfter(absPath, strlength(root));
    if startsWith(rel, filesep); rel = extractAfter(rel, 1); end
else
    rel = absPath;
end
rel = replace(rel, "\", "/");
end

function tf = shouldExclude(relPath, patterns)
tf = false;
segs = string(strsplit(relPath, "/"));
for k = 1:numel(patterns)
    p = patterns(k);
    if contains(p, "*")
        % Glob pattern (e.g. "*.stackdump"): match any single path segment.
        regex = "^" + replace(replace(p, ".", "\."), "*", ".*") + "$";
        for j = 1:numel(segs)
            if ~isempty(regexp(segs(j), regex, "once"))
                tf = true; return
            end
        end
    else
        % Literal pattern: match if it's a path segment OR the whole path.
        if any(segs == p) || relPath == p
            tf = true; return
        end
    end
end
end
