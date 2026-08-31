/// Editorial content for the News and History tabs.
///
/// This is a local seed list, not a feed. Nothing here is fetched,
/// so every entry has to be something we actually know to be true —
/// the seed items below are drawn from the published 2027 Snan
/// schedule only. Add real articles as they are confirmed, or
/// replace `kKumbhNews` with an API call when the backend grows a
/// /news endpoint.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.summary,
    required this.date,
    required this.tag,
    this.url,
    this.imageUrl,
    this.source,
  });

  final String title;
  final String summary;

  /// Display date for the item, e.g. 'Aug 2027'.
  final String date;

  /// Section chip: 'Kumbh 2027', 'Kumbh 2026', 'Advisory'.
  final String tag;

  /// Optional source link, opened in the browser.
  final String? url;

  /// Optional article image, shown above the card body when present.
  final String? imageUrl;

  /// Publisher name, e.g. 'The Indian Express' — live articles only.
  final String? source;
}

const List<NewsItem> kKumbhNews = [
  NewsItem(
    title: 'Simhastha Kumbh 2027 bathing schedule announced',
    summary:
        'The Nashik–Trimbakeshwar Simhastha runs from 17 July to 15 '
        'September 2027, opening with Karka Sankranti and closing on '
        'Bhadrapada Purnima.',
    date: 'Schedule',
    tag: 'Kumbh 2027',
  ),
  NewsItem(
    title: 'Three Amrit Snan dates confirmed',
    summary:
        '2 August, 31 August and 11–12 September 2027 are the royal '
        'bathing days. The final Snan is split between the Vaishnava '
        'Akhadas at Ramkund and the Shaiva Akhadas at Kushavarta Kund.',
    date: 'Schedule',
    tag: 'Kumbh 2027',
  ),
  NewsItem(
    title: '31 August expected to draw the largest crowds',
    summary:
        'Shravan Amavasya is the peak royal bathing day of the season. '
        'Book accommodation early — tent pricing surges to 2.5x on this '
        'date.',
    date: 'Advisory',
    tag: 'Advisory',
  ),
  NewsItem(
    title: 'Secondary Parva Snan dates still provisional',
    summary:
        'Some published calendars list additional Parva Snan dates as '
        'not yet final. Only the three Amrit Snans should be treated as '
        'fixed when planning travel.',
    date: 'Advisory',
    tag: 'Advisory',
  ),
];

/// A history video for the History tab.
///
/// `url` should be a full YouTube (or other) link — it is opened in
/// the external browser / YouTube app via url_launcher. `thumbnail`
/// may be a network URL or a bundled asset path; leave it null to
/// fall back to a saffron placeholder.
class HistoryVideo {
  const HistoryVideo({
    required this.title,
    required this.description,
    required this.url,
    this.duration,
    this.thumbnail,
  });

  final String title;
  final String description;
  final String url;
  final String? duration;
  final String? thumbnail;
}

/// Empty until the videos are supplied. The History tab renders an
/// explicit "coming soon" state while this list is empty rather than
/// showing a blank screen.
const List<HistoryVideo> kHistoryVideos = <HistoryVideo>[
  // Example of the shape to add:
  // HistoryVideo(
  //   title: 'Origins of the Simhastha Kumbh',
  //   description: 'Why Nashik and Trimbakeshwar host the Kumbh.',
  //   url: 'https://youtu.be/QS7vZj9-OAc?si=bKQd8Q2XmiyzSa3N',
  //   duration: '8:24',
  // ),
];

/// Static background on the Kumbh, shown above the videos so the
/// History tab is useful even before any video is added.
const List<Map<String, String>> kHistorySections = [
  {
    'title': '१. पौराणिक उगम',
    'image': 'assets/history/samudra_manthan.jpeg',
    'body':
        'हिंदू पौराणिक कथेनुसार, कुंभ मेळ्याचा संबंध समुद्रमंथनाशी आहे.\n\n'
        'देव आणि असुर यांनी अमृत म्हणजेच अमरत्व देणारे अमृत मिळवण्यासाठी '
        'समुद्राचे मंथन केले. समुद्रमंथनातून अमृत कुंभात (घटात) प्रकट झाले. '
        'हे अमृत मिळवण्यासाठी देव आणि असुरांमध्ये संघर्ष झाला.\n\n'
        'परंपरेनुसार, या संघर्षादरम्यान अमृताचे थेंब पृथ्वीवरील चार '
        'ठिकाणी पडले:\n'
        '• प्रयागराज – गंगा, यमुना आणि पौराणिक सरस्वतीचा संगम\n'
        '• हरिद्वार – गंगा नदी\n'
        '• नाशिक – गोदावरी नदी\n'
        '• उज्जैन – क्षिप्रा नदी\n\n'
        'ही चार ठिकाणे कुंभ मेळ्याची प्रमुख केंद्रे बनली.',
  },
  {
    'title': '२. ऐतिहासिक विकास',
    'image': 'assets/history/ghats_sunset.png',
    'body':
        'पवित्र नद्यांच्या काठी धार्मिक सभा घेण्याची परंपरा आधुनिक कुंभ '
        'मेळ्यापेक्षा खूप जुनी आहे. लोक पवित्र ठिकाणी स्नान, पूजा, ध्यान '
        'आणि धार्मिक विधी करण्यासाठी एकत्र येत असत.\n\n'
        'इ.स. 7व्या शतकात, चिनी प्रवासी ह्युएन त्सांग (Xuanzang) यांनी '
        'सम्राट हर्षवर्धनाच्या काळात प्रयागराज येथे झालेल्या एका मोठ्या '
        'धार्मिक सभेचे वर्णन केले आहे. इतिहासकार या सभेला नंतरच्या मोठ्या '
        'धार्मिक मेळ्यांचा एक महत्त्वाचा पूर्वरूप मानतात; मात्र ती सभा '
        'आजच्या स्वरूपातील कुंभ मेळाच होती असे निश्चितपणे म्हणता येत '
        'नाही.\n\n'
        'पुढील अनेक शतकांमध्ये तीर्थयात्री, संत, साधू आणि विविध धार्मिक '
        'समुदाय मोठ्या संख्येने एकत्र येऊ लागले आणि या धार्मिक परंपरा '
        'अधिक संघटित होत गेल्या.',
  },
  {
    'title': '३. आखाडे आणि साधू',
    'image': 'assets/history/naga_sadhus.png',
    'body':
        'आखाडे, म्हणजे संघटित साधू आणि संन्याशांचे धार्मिक गट, कुंभ '
        'मेळ्याचा महत्त्वाचा भाग बनले.\n\n'
        'विशेषतः नागा साधू कुंभ मेळ्यातील प्रमुख स्नान सोहळ्यांमध्ये '
        'सहभागी होण्यासाठी प्रसिद्ध आहेत.\n\n'
        'कुंभ मेळा धार्मिक समुदायांसाठी एकत्र येण्याचे, धार्मिक विधी '
        'करण्याचे, आध्यात्मिक ज्ञान देण्याचे आणि साधना करण्याचे महत्त्वाचे '
        'ठिकाण बनले.',
  },
  {
    'title': '४. कुंभ मेळा दर 12 वर्षांनी का येतो?',
    'image': 'assets/history/twelve_years.png',
    'body':
        'कुंभ मेळ्याच्या तारखा पारंपरिक हिंदू ज्योतिषशास्त्रावर आधारित '
        'असतात. त्यामध्ये विशेषतः गुरू (बृहस्पती) आणि सूर्याच्या '
        'स्थितीचा तसेच इतर खगोलीय गणनांचा विचार केला जातो.\n\n'
        'प्रत्येक प्रमुख कुंभस्थळी संबंधित ज्योतिषीय स्थिती साधारणपणे 12 '
        'वर्षांनी येते.\n\n'
        'कुंभ मेळ्याचे प्रमुख प्रकार:\n'
        '• पूर्ण कुंभ – एका ठिकाणी साधारणपणे दर 12 वर्षांनी\n'
        '• अर्ध कुंभ – साधारणपणे दर 6 वर्षांनी, मुख्यतः प्रयागराज आणि '
        'हरिद्वार येथे\n'
        '• महाकुंभ – पारंपरिक मान्यतेनुसार प्रयागराज येथे साधारण 144 '
        'वर्षांनी\n\n'
        'कुंभची चार प्रमुख ठिकाणे: प्रयागराज → हरिद्वार → नाशिक → '
        'उज्जैन.\n\n'
        'कुंभच्या अचूक तारखा केवळ ठराविक कॅलेंडरनुसार नसून पारंपरिक '
        'ज्योतिषीय गणनेनुसार निश्चित केल्या जातात.',
  },
  {
    'title': '५. ब्रिटिश काळातील कुंभ',
    'image': 'assets/history/british_period.png',
    'body':
        'ब्रिटिश राजवटीदरम्यान कुंभ मेळ्यातील मोठ्या गर्दीमुळे '
        'प्रशासनाला अनेक महत्त्वाच्या गोष्टींची व्यवस्था करावी लागली: '
        'गर्दीचे व्यवस्थापन, स्वच्छता, पिण्याचे पाणी, वाहतूक, पोलीस '
        'व्यवस्था आणि सार्वजनिक आरोग्य.\n\n'
        'यामुळे मोठ्या धार्मिक यात्रांचे व्यवस्थापन करण्यासाठी '
        'प्रशासकीय पद्धती अधिक विकसित झाल्या.',
  },
  {
    'title': '६. स्वातंत्र्यानंतरचा कुंभ',
    'image': 'assets/history/post_independence.png',
    'body':
        '1947 नंतर कुंभ मेळ्याचा विस्तार मोठ्या प्रमाणात झाला.\n\n'
        'आधुनिक सरकारांनी मोठ्या प्रमाणावर तात्पुरती पायाभूत सुविधा '
        'उपलब्ध करून देण्यास सुरुवात केली, ज्यामध्ये: रस्ते आणि पूल, '
        'रुग्णालये आणि वैद्यकीय सुविधा, वीज व्यवस्था, पाणीपुरवठा, '
        'स्वच्छता व्यवस्था, पोलीस आणि आपत्कालीन सेवा, तात्पुरती निवास '
        'व्यवस्था आणि वाहतूक व्यवस्था यांचा समावेश होतो.\n\n'
        'यामुळे कुंभ मेळा केवळ धार्मिक आयोजन न राहता मोठ्या प्रमाणावर '
        'तात्पुरते शहर उभारण्याचे आणि गर्दीचे व्यवस्थापन करण्याचे एक '
        'उल्लेखनीय उदाहरण बनला.',
  },
  {
    'title': '७. आजचा कुंभ मेळा',
    'image': 'assets/history/kumbh_today.png',
    'body':
        'आज लाखो लोक कुंभ मेळ्यात सहभागी होण्यासाठी प्रवास करतात. ते '
        'पवित्र नदीत स्नान, पूजा, संतांचे दर्शन आणि धार्मिक कार्यक्रमांमध्ये '
        'सहभाग घेतात.\n\n'
        'कुंभ मेळ्यातील सर्वात महत्त्वाच्या कार्यक्रमांपैकी एक म्हणजे '
        'अमृत स्नान, ज्यामध्ये महत्त्वाच्या पर्वदिनी साधू आणि भाविक पवित्र '
        'नदीत सामूहिक स्नान करतात.',
  },
  {
    'title': '🕉️ कुंभ मेळ्याची सोपी कालरेषा',
    'body':
        'प्राचीन भारत\n'
        '↓\n'
        'पवित्र नद्यांच्या काठी तीर्थयात्रा आणि धार्मिक परंपरांचा विकास\n'
        '↓\n'
        'समुद्रमंथनाची पौराणिक परंपरा\n'
        '↓\n'
        'अमृताचे थेंब चार पवित्र ठिकाणी पडल्याची मान्यता\n'
        '↓\n'
        'इ.स. 7वे शतक — ह्युएन त्सांग यांनी प्रयागराजमधील मोठ्या धार्मिक '
        'सभेचे वर्णन केले\n'
        '↓\n'
        'मध्ययुगीन काळ — साधू, आखाडे आणि संघटित तीर्थयात्रांचा विकास\n'
        '↓\n'
        'ब्रिटिश काळ — मोठ्या प्रमाणावर प्रशासन आणि गर्दी '
        'व्यवस्थापनाचा विकास\n'
        '↓\n'
        '1947 नंतर — आधुनिक पायाभूत सुविधा आणि सरकारी व्यवस्थापन\n'
        '↓\n'
        'आज — कुंभ मेळा जगातील सर्वात मोठ्या धार्मिक आणि सांस्कृतिक '
        'मेळ्यांपैकी एक.',
  },
  {
    'title': 'थोडक्यात',
    'body':
        'कुंभ मेळा भारतातील पवित्र नद्यांच्या काठी तीर्थयात्रा करण्याच्या '
        'प्राचीन परंपरेतून अनेक शतकांच्या कालावधीत विकसित झाला. त्याचा '
        'आध्यात्मिक आधार समुद्रमंथनाच्या कथेत आहे, तर त्याचे ऐतिहासिक '
        'स्वरूप प्रयागराज, हरिद्वार, नाशिक आणि उज्जैन येथील धार्मिक '
        'सभांमधून हळूहळू विकसित झाले. एका ठिकाणी कुंभ मेळा साधारणपणे दर '
        '12 वर्षांनी येतो, तर प्रयागराज आणि हरिद्वार येथे अर्ध कुंभ '
        'साधारणपणे दर 6 वर्षांनी आयोजित केला जातो.',
  },
];
