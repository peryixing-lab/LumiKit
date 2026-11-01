export class LumiHelpRouteParam {
  articleId: string = '';
}

export class LumiHelpNavigation {
  static open(stack: NavPathStack, articleId: string): void {
    const param: LumiHelpRouteParam = new LumiHelpRouteParam();
    param.articleId = articleId;
    stack.pushPathByName('help', param);
  }
}
