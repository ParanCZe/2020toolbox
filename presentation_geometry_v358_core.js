(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.presentationGeometryV358=api;
})(typeof window!=='undefined'?window:globalThis,function(){
  const PT_PER_MM=72/25.4;
  function clamp(v,min,max){return Math.max(min,Math.min(max,v))}
  function resizeMediaFromWidth({widthNorm,aspect,canvasW,canvasH}){
    const safeAspect=Math.max(0.000001,Number(aspect)||1);
    const w=Number(widthNorm)||0;
    const h=((w*(Number(canvasW)||1))/safeAspect)/(Number(canvasH)||1);
    return {widthNorm:w,heightNorm:h};
  }
  function scaledFontSize(baseSize,scale,min=6,max=144){
    return clamp(Math.round((Number(baseSize)||16)*(Number(scale)||1)*10)/10,min,max);
  }
  function guideInsetPx({pageWidthPt,renderedWidthPx,insetMm=5}){
    const pt=Number(pageWidthPt)||1,px=Number(renderedWidthPx)||0;
    return (Number(insetMm)||0)*PT_PER_MM*(px/pt);
  }
  return {PT_PER_MM,clamp,resizeMediaFromWidth,scaledFontSize,guideInsetPx};
});
