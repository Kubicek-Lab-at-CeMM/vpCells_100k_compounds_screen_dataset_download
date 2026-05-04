# vpCells dataset: 100k compounds screen with pool of 7 clones

The 105k screen dataset comprises **325 measurements**, each corresponding to one 384-well microplate. For each measurement, three files are provided:
1. Data zip file (e.g., `2340006__2023-11-17T03_16_52-Measurement_1.zip`)
2. Filelist with names of folders/files in the zip file (e.g., `2340006__2023-11-17T03_16_52-Measurement_1.zip.filelist`)
3. sha256 checksum of the data zip file  (e.g., `2340006__2023-11-17T03_16_52-Measurement_1.zip.sha256`)


### Experimental conditions
Cells were imaged 6 hours after compound treatment with an Opera Phenix high-content confocal microscopy system with water immersion objective (40× magnification), capturing 5-channel images at 1,080 × 1,080 pixel resolution. We imaged 5 fields of view (FOVs) per well, with the exception of an initial batch of plates (2340001 through 2340011, with 3 FOVs per well).

![image.png](../testik.jpg)

### Contents of each measurement folder
- `Images`: raw images
    - one tiff file for each image and channel, with the following naming convention (listing relevant fields only):
    - example: `r11c06f04p01-ch3sk1fk1fl1.tiff`
        - `r11`: row 11 of the plate
        - `c06`: column 6 of the plate
        - `f04`: field 4 (imaging position within the well)
        - `ch3`: channel 3
    - please note that channels were renumbered for the analysis (see table below) 
- `FFC_Profile`: contains an XML file with parameters for flatfield correction
- `Images_FFC`:  flatfield-corrected images in tiff format, generated with the Harmony software provided by the instrument manufacturer (Revvity)
    - please note that channel numbers here differ from those in the raw images folder (see table below)
- `Images_segmented`: segmentation masks in png format
    - `ch4sk1fk1fl1_segmented_mask.png`: cellpose segmentation masks of entire cells from membrane marker (channel 4, mAmetrine)
	- `ch5sk1fk1fl1_segmented_mask.png`: nuclAIzer segmentation masks of nuclei from nuclear marker (channel 5, miRFP)
	- `_filtered_cells.png`: masks of entire cells after 1:1 mapping to nuclei and quality filtering
	- `_filtered_nuclei.png`: masks of nuclei after 1:1 to cells and quality filtering
	- `_filtered_cytoplasm.png`: masks of the cytoplasmic part of the cell object (entire cell minus nucleus) for cells that passed 1:1 mapping and quality filtering
- `CellProfiler_measurements`: CellProfiler features extracted for cells and images
- `Predictions_CellProfiler_RF`: single-cell level clone identity predictions from random forest model calculated from CellProfiler features

| Channel name (fluorophore) | Description | Channel number (FFC-corrected images folder, analysis) | Channel number (raw images folder only) |
| :--- | :--- | :--- | :---- |
| GFP | Tagged protein of interest   1 | 1 | 3 |
| mScarlet | Tagged protein of interest 2 | 2 | 5 |
| BFP | Visual barcode | 3 | 1 |
| mAmetrine | Membrane marker | 4 | 2 |
| miRFP | Nuclear marker | 5 | 4 |


## Platemap file

|   well_ID |   plate | measurement                                    | well   |   row |   column | compound   |   AssayConc_uM | Type   | Transfer   | is_control   |   measurement_batch | Sublibrary                                |
|----------:|--------:|:-----------------------------------------------|:-------|------:|---------:|:-----------|---------------:|:-------|:-----------|:-------------|--------------------:|:------------------------------------------|
|     13658 | 2340036 | 2340036__2023-12-03T00_43_50-Measurement_1_FFC | J03    |    10 |        3 | T0507-2811 |             10 | Cpd    | YES        | no           |                   9 | Chemical diversity library                |
|     18678 | 2340049 | 2340049__2023-12-08T01_34_26-Measurement_1_FFC | K07    |    11 |        7 | DMSO       |            nan | DMSO   | YES        | yes          |                  11 | Other (controls)                          |
|     25034 | 2340066 | 2340066__2023-12-15T04_14_41-Measurement_1_FFC | D03    |     4 |        3 | T6924604   |             10 | Cpd    | YES        | no           |                  13 | Chemical diversity library                |
|     34926 | 2340089 | 2340089__2023-12-17T14_20_02-Measurement_1_FFC | P07    |    16 |        7 | IC043452.1 |             10 | Cpd    | YES        | no           |                  14 | Chemical diversity library                |
|     42932 | 2340111 | 2340111__2024-01-06T06_55_55-Measurement_1_FFC | M21    |    13 |       21 | IC080190.1 |             10 | Cpd    | YES        | no           |                  20 | Chemical diversity library                |
|     57968 | 2340150 | 2340150__2024-01-19T01_37_29-Measurement_1_FFC | P09    |    16 |        9 | IC069849.1 |             10 | Cpd    | YES        | no           |                  27 | Chemical diversity library                |
|     69782 | 2340181 | 2340181__2024-01-25T06_18_37-Measurement_1_FFC | L15    |    12 |       15 | DMSO       |            nan | DMSO   | YES        | yes          |                  30 | Other (controls)                          |
|     92989 | 2340242 | 2340242__2024-02-10T10_05_05-Measurement_1_FFC | C14    |     3 |       14 | IC024528.1 |             10 | Cpd    | YES        | no           |                  39 | Chemical diversity library                |
|    100569 | 2340261 | 2340261__2023-12-01T06_12_47-Measurement_1_FFC | O10    |    15 |       10 | Z908000502 |             10 | Cpd    | YES        | no           |                   7 | Chemical diversity library, cytotoxic set |
|    118349 | 2340308 | 2340308__2025-01-11T07_36_28-Measurement_1_FFC | D06    |     4 |        6 | Troxerutin |             10 | Cpd    | YES        | no           |                  48 | FDA-approved drugs                        |
