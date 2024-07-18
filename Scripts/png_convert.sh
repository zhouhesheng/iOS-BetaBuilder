for f in $(find . -name "*.png")
do
  xcrun -sdk iphoneos pngcrush -revert-iphone-optimizations $f temp.png
  mv temp.png $f
done
