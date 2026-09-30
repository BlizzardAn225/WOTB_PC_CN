@echo off

if exist "%userprofile%\AppData\Local\wotblitz\DavaProject" (
rmdir /S /Q "%userprofile%\AppData\Local\wotblitz\DavaProject"
color 0A
echo DavaProject folder was removed.
color
)

if exist "%userprofile%\AppData\Local\wotblitz\packs" (
rmdir /S /Q "%userprofile%\AppData\Local\wotblitz\packs"
color 0A
echo packs folder was removed.
color
)

if exist "%userprofile%\AppData\Local\Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\DAVAProject" (
rmdir /S /Q "%userprofile%\AppData\Local\Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\DAVAProject"
color 0A
echo DavaProject store folder was removed.
color
)

if exist "%userprofile%\AppData\Local\Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\packs" (
rmdir /S /Q "%userprofile%\AppData\Local\Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\packs"
color 0A
echo packs store folder was removed.
color
)

color 0A
echo all temp files were deleted successfully
color
@pause && exit 
