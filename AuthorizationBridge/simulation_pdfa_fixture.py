"""Create an independently verifiable, unsigned PDF/A-3b-style drawing test fixture.
Not a claim of compliance: real veraPDF validation runs AFTER CMS signing.
"""
import io
from pathlib import Path
from PIL import ImageCms, Image, ImageDraw, ImageFont
from reportlab.pdfgen import canvas
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (NameObject, NumberObject, ArrayObject, DictionaryObject,
                           TextStringObject, DecodedStreamObject)


def create_simulated_ear_stamp() -> bytes:
    """Realistic looking, EXPLICITLY INVALID laboratory authorization graphic."""
    img = Image.new("RGB", (1150, 300), "white")
    draw = ImageDraw.Draw(img)
    regular = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    large = ImageFont.truetype(regular, 32)
    small = ImageFont.truetype(regular, 23)
    badge = ImageFont.truetype(regular, 25)
    red = (198, 42, 56)
    draw.ellipse((24, 22, 270, 270), outline=red, width=10)
    draw.ellipse((49, 47, 245, 245), outline=red, width=4)
    draw.text((79, 91), "LAB", font=ImageFont.truetype(regular, 44), fill=red)
    draw.text((72, 159), "SIMULACE", font=badge, fill=red)
    draw.text((315, 50), "VZOR - NEPLATNE AUTORIZACNI RAZITKO", font=large, fill=(35, 39, 44))
    draw.text((315, 121), "20-20 LAB  |  Testovaci autorizovana osoba", font=small, fill=(35, 39, 44))
    draw.text((315, 172), "Podpis: LAB CA 4  /  casove razitko: LAB TSA CA 5", font=small, fill=(35, 39, 44))
    draw.text((315, 225), "POUZE SIMULACE - NENI URCENO PRO URAD", font=small, fill=red)
    stream = io.BytesIO()
    img.save(stream, format="PNG")
    return stream.getvalue()


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
    # Architectural content intentionally resembles a real technical drawing:
    # double walls, doors, furniture, room dimensions and a title block.
    page.setLineWidth(1.8)
    page.line(120, 265, 680, 265)
    page.line(120, 268, 680, 268)
    page.line(370, 150, 370, 420)
    page.line(373, 150, 373, 420)
    page.setLineWidth(0.9)
    for x, y, w, h in [(200,310,68,50),(437,311,85,55),(530,198,95,36),
                       (180,180,120,35),(412,193,60,50)]:
        page.rect(x,y,w,h)
    for x, y, r in [(220,320,12),(455,330,16),(545,216,11),(601,216,11)]:
        page.circle(x,y,r)
    page.setDash(3,4)
    page.line(105, 282, 699, 282)
    page.line(380, 139, 380, 438)
    page.setDash()
    page.setFont("SimEmbedded", 11)
    for label,x,y in [("01  VSTUP",140,395),("02  OBYVACI POKOJ",420,395),
                       ("03  KUCHYNE",420,277),("04  POKOJ",150,250),
                       ("05  CHODBA",316,287)]:
        page.drawString(x,y,label)
    # Dimension chains.
    page.setLineWidth(0.5)
    page.line(120,450,680,450)
    for x in (120,370,680):
        page.line(x,441,x,459)
    page.drawCentredString(244,454,"4200")
    page.drawCentredString(529,454,"5200")
    # Technical title block intentionally leaves room for real signature widget.
    page.setLineWidth(1.0)
    page.rect(52,30,770,82)
    page.line(536,30,536,112)
    page.line(52,69,536,69)
    page.setFont("SimEmbedded", 10)
    page.drawString(65,87,"20-20 LAB  |  ARCHITEKTONICKO STAVEBNI RESENI")
    page.drawString(65,49,"SO01 - PUDORYS 1.NP  |  MERITKO 1:100  |  FORMAT A3")
    page.drawString(547,113,"ELEKTRONICKE AUTORIZACNI RAZITKO (LAB)")
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
