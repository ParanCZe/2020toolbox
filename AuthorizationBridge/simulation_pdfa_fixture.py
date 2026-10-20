"""Create an independently verifiable, unsigned PDF/A-3b-style drawing test fixture.
Not a claim of compliance: real veraPDF validation runs AFTER CMS signing.
"""
import io
from pathlib import Path
from PIL import ImageCms
from reportlab.pdfgen import canvas
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (NameObject, NumberObject, ArrayObject, DictionaryObject,
                           TextStringObject, DecodedStreamObject)


def create_simulated_drawing_pdfa():
    font_candidates = (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    )
    path = next((x for x in font_candidates if Path(x).is_file()), None)
    if not path:
        raise RuntimeError("Missing embedded font for PDF/A synthetic drawing.")
    pdfmetrics.registerFont(TTFont("SimEmbedded", path))
    data = io.BytesIO()
    page = canvas.Canvas(data, pagesize=(841.8898, 595.2756),
                         pageCompression=0, pdfVersion=(1, 7), invariant=1)
    page.setFont("SimEmbedded", 18)
    page.drawString(40, 550, "20-20 LAB: SIMULOVANY ARCHITEKTONICKY VYKRES")
    page.setFont("SimEmbedded", 11)
    page.drawString(40, 526, "JEN TEST - ani autorizace, ani dokument pro stavebni urad")
    for x in range(60, 800, 40):
        page.line(x, 105, x, 480)
    for y in range(105, 481, 40):
        page.line(60, y, 800, y)
    page.setLineWidth(3)
    page.rect(120, 150, 560, 270)
    page.setLineWidth(1)
    page.rect(160, 190, 210, 185)
    page.rect(390, 190, 245, 185)
    page.drawString(105, 76, "PUDORYS, orientacni geometrie. LAB CA 4 + LAB CA 5 + RFC3161 TEST.")
    page.save()
    data.seek(0)
    source = PdfReader(data)
    writer = PdfWriter()
    writer.add_page(source.pages[0])
    title = "20-20 LAB: SIMULOVANY ARCHITEKTONICKY VYKRES"
    producer = "20-20 LAB PDF/A-3b simulator"
    writer.add_metadata({"/Title": title, "/Creator": producer, "/Producer": producer})
    icc = DecodedStreamObject()
    icc.set_data(ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    icc.update({NameObject("/N"): NumberObject(3)})
    intent = DictionaryObject({
        NameObject("/Type"): NameObject("/OutputIntent"),
        NameObject("/S"): NameObject("/GTS_PDFA1"),
        NameObject("/OutputConditionIdentifier"): TextStringObject("sRGB IEC61966-2.1"),
        NameObject("/Info"): TextStringObject("sRGB IEC61966-2.1"),
        NameObject("/DestOutputProfile"): writer._add_object(icc),
    })
    writer._root_object[NameObject("/OutputIntents")] = ArrayObject(
        [writer._add_object(intent)]
    )
    xmp = """<?xpacket begin="\ufeff" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" pdfaid:part="3" pdfaid:conformance="B" />
<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title><rdf:Alt><rdf:li xml:lang="x-default">20-20 LAB: SIMULOVANY ARCHITEKTONICKY VYKRES</rdf:li></rdf:Alt></dc:title></rdf:Description>
<rdf:Description rdf:about="" xmlns:pdf="http://ns.adobe.com/pdf/1.3/" pdf:Producer="20-20 LAB PDF/A-3b simulator" />
<rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:CreatorTool="20-20 LAB PDF/A-3b simulator" />
</rdf:RDF></x:xmpmeta>
<?xpacket end="w"?>"""
    meta = DecodedStreamObject()
    meta.set_data(xmp.encode("utf-8"))
    meta.update({NameObject("/Type"): NameObject("/Metadata"),
                 NameObject("/Subtype"): NameObject("/XML")})
    writer._root_object[NameObject("/Metadata")] = writer._add_object(meta)
    result = io.BytesIO()
    writer.write(result)
    return result.getvalue()
