import SwiftUI

struct RelatedLinksView: View {
    var body: some View {
        Form {
            Section {
                ForEach(RelatedSite.all) { site in
                    SystemText(site.title, linkURL: URL(string: site.address))
                }
            }
        }
        .appPageStyle()
        .navigationTitle(ui("友情連結"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RelatedSite: Identifiable {
    let title: String
    let address: String
    var id: String { address }

    // Android's complete dialect-links menu, in its original order, followed
    // by the additional resources. Site names intentionally stay in Chinese.
    // Source: osfans/MCPDict 232064ec009e524f2299bea9cc29602c667a22cc,
    // app/src/main/res/menu/main.xml and res/values/strings.xml.
    static let all: [RelatedSite] = [
        .init(title: "方言相似度", address: "https://mcpdict.sourceforge.io/sim.html"),
        .init(title: "淮語詞典", address: "https://jianghuaidict.sourceforge.io/"),
        .init(title: "泰如辭典", address: "https://taerv.sourceforge.io/"),
        .init(title: "唯二網頁版", address: "https://mcpdict.vear.vip/"),
        .init(title: "汉字音典小程序", address: "https://mcpdict.vear.vip/assets/miniapp_qrcode.webp"),
        .init(title: "綾香網頁版", address: "https://nk2028.shn.hk/yindian/"),
        .init(title: "方音圖鑑", address: "https://dialects.yzup.top"),
        .init(title: "薪典深耕版", address: "https://c.syndict.com/zi"),
        .init(title: "字統網", address: "https://zi.tools/"),
        .init(title: "韻典網", address: "https://ytenx.org/"),
        .init(title: "中国语言资源保护工程", address: "https://zhongguoyuyan.cn/index"),
        .init(title: "古音小鏡", address: "http://www.kaom.net/"),
        .init(title: "切韻音系推導器", address: "https://nk2028.shn.hk/tshet-uinh-deriver/"),
        .init(title: "東方語言學", address: "http://www.eastling.org/"),
        .init(title: "小學堂", address: "https://xiaoxue.iis.sinica.edu.tw/"),
        .init(title: "漢語多功能字庫", address: "https://humanum.arts.cuhk.edu.hk/Lexis/lexi-mf/"),
        .init(title: "字海（叶典）", address: "http://yedict.com/")
    ]
}
