from pathlib import Path

# Patch inserted media export so crop stays vector for embedded PDF.
p=Path('presentation_media_v331.js')
s=p.read_text(encoding='utf-8')
helper="""
  function drawMediaWithCrop(pg,o,x,y,width,height,draw){
    const pts=o?.cropPoints;
    if(!pts||pts.length<3){draw();return}
    const ops=[PDFLib.pushGraphicsState(),PDFLib.moveTo(x+pts[0].x*width,y+(1-pts[0].y)*height)];
    for(let i=1;i<pts.length;i++)ops.push(PDFLib.lineTo(x+pts[i].x*width,y+(1-pts[i].y)*height));
    ops.push(PDFLib.closePath(),PDFLib.clip(),PDFLib.endPath());
    pg.pushOperators(...ops);draw();pg.pushOperators(PDFLib.popGraphicsState());
  }
"""
anchor="  async function dataUrlBuffer(data){return fetch(data).then(r=>r.arrayBuffer())}\n"
if 'function drawMediaWithCrop(' not in s and anchor in s:
    s=s.replace(anchor,anchor+helper,1)
s=s.replace("if(embedded?.[0]){pg.drawPage(embedded[0],{x,y,width,height});continue}","if(embedded?.[0]){drawMediaWithCrop(pg,o,x,y,width,height,()=>pg.drawPage(embedded[0],{x,y,width,height}));continue}")
s=s.replace("pg.drawImage(img,{x,y,width,height});","drawMediaWithCrop(pg,o,x,y,width,height,()=>pg.drawImage(img,{x,y,width,height}));")
p.write_text(s,encoding='utf-8')

# Patch moodboard export clipping to support arbitrary polygon crop without rasterizing.
p=Path('index.html')
s=p.read_text(encoding='utf-8')
old="""              targetPage.pushOperators(
                pushGraphicsState(),
                rectangle(cell.x, cellBottomY, cell.w, cell.h),
                clip(),
                endPath()
              );
              targetPage.drawImage(imageObj, { x: dx, y: dy, width: drawW, height: drawH });
              targetPage.pushOperators(popGraphicsState());"""
new="""              if (cell.cropPoints && cell.cropPoints.length >= 3) {
                const pts = cell.cropPoints;
                const ops = [pushGraphicsState(), moveTo(cell.x + pts[0].x * cell.w, cellBottomY + (1 - pts[0].y) * cell.h)];
                for (let pi = 1; pi < pts.length; pi++) ops.push(lineTo(cell.x + pts[pi].x * cell.w, cellBottomY + (1 - pts[pi].y) * cell.h));
                ops.push(closePath(), clip(), endPath());
                targetPage.pushOperators(...ops);
              } else {
                targetPage.pushOperators(
                  pushGraphicsState(),
                  rectangle(cell.x, cellBottomY, cell.w, cell.h),
                  clip(),
                  endPath()
                );
              }
              targetPage.drawImage(imageObj, { x: dx, y: dy, width: drawW, height: drawH });
              targetPage.pushOperators(popGraphicsState());"""
if old in s:
    s=s.replace(old,new,1)

loader='<script src="presentation_source_crop_v333.js?v=333"></script>'
if loader not in s:
    marker='<script src="sketchup_extension_button_v330.js?v=330"></script>'
    if marker in s:s=s.replace(marker,marker+'\n'+loader,1)
    else:s=s.replace('</body>',loader+'\n</body>',1)
p.write_text(s,encoding='utf-8')
print('V3.33 vector crop/source patch applied')
